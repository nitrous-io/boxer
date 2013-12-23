ConvertSize = require './convert_size'
ResourcePool = require './resource_pool'
settings = require '../../config/settings'
escapeShellArg = require('./utils').escapeShellArg
redisStoreSettings = require('../../config/settings').redisStore
redisClient = require('./utils').initRedisClientWith(redisStoreSettings, "localStore")
scriptPath = __dirname.replace('app/lib', 'scripts/')
childProcess = require 'child_process'
os = require 'os'

async = require 'async'
_ = require 'underscore'

http = require 'http'

module.exports = class Box
  @UID_BASE = 15000
  @SWAPPINESS = 60
  @CPU_SHARES = 512

  constructor: (@id) ->
    @ip = @gateway = @interface = @port = @boxerCallback = null
    @containerState = 'stopped'
    @name = @containerTemplate = null
    @memory = @diskSpace = @virtualMemory = @publicKeys = @snapshotURL = null

    @swappiness = Box.SWAPPINESS
    @cpuShares = Box.CPU_SHARES

    @disk = null
    @boxerId = null
    # basic authentication for box
    @authUsername = @authPassword = null
    @aufs = false
    @mount = null
    @quotaMethod = null
    @selectedVG = null
    @premium = null

  containerName: -> "#{@name}-#{@id}"

  # return the proper mount method of the box
  # valid mount methods are lvm / aufs / overlayfs
  mountMethod: ->
    return "lvm" if @mount == "lvm"
    return "aufs" if @aufs || @mount == "aufs"
    "overlayfs"

  # return the proper quota method of the box
  # valid value are usrquota/projquota
  getQuotaMethod: ->
    return "usrquota" if @quotaMethod == "usrquota"
    "prjquota"

  # block limit is the maximum number of block that @diskLimit can contain
  # for linux, this is typically @diskLimit in KB as 1 block is 1024 bytes
  #
  # cat /usr/include/x86_64-linux-gnu/sys/mount.h | grep BLOCK_SIZE
  # #define BLOCK_SIZE      1024
  getBlockLimit: ->
    parseInt(parseInt(@diskSpace) * 1024)

  valid: (opts) ->
    attributesToValidate = []
    self = this

    if opts?.onCreate?
      attributesToValidate = ['id', 'name', 'containerTemplate', 'memory', 'diskSpace', 'disk']
    else
      attributesToValidate = ['id', 'name']

    _.reduce attributesToValidate, (memo, attribute) ->
      memo && self[attribute]?
    , true

  create: (@successCallback, @failCallback) ->
    if this.valid()
      async.waterfall [
        (cb) => this._acquireResources cb
        (cb) => this._prepareContainer (err) -> cb(err)
        (cb) => this._mountContainer (err) -> cb(err)
        (cb) => this._configureBox (err) -> cb(err)
        (cb) => this._setUpPortForwarding (err) -> cb(err)
        (cb) => this._setDefaultKeyPair (err) -> cb(err)
        (cb) => this._savePublicKeys (err) -> cb(err)
        (cb) => this._setPremium (err) -> cb(err)
        (cb) =>
          try this.save cb
          catch e then cb(new Error("Failed to save #{this.containerName()}: #{e}"))
      ], (err) =>
        return @successCallback() unless err
        this.destroy =>
          @failCallback(new Error("fail to create #{this.containerName()}"))
    else
      @failCallback(new Error('Invalid Params'))

  start: (specs, cb) ->
    if this.valid()
      self = this
      self._mountContainer ->
        self._changeCPUShares specs, (err) ->
          return cb(new Error('Cannot change CPU shares')) if err
          self._changeMemoryLimit specs, (err) ->
            return cb(new Error('Cannot change the memory limit')) if err
            self._startContainer ->
              self.updateAttributes containerState: 'running', cb
    else
      cb(new Error('Invalid Params'))

  memoryUnit: ->
    ConvertSize.unit @memory

  # totalMemory is the sum of the memory and swap allocated to the box.
  # This is used for the lxc.cgroup.memory.memsw.limit_in_bytes setting in LXC.
  totalMemory: ->
    return null unless @memory
    if @virtualMemory
      memoryKb = ConvertSize.convert(@memory)
      virtualMemoryKb = ConvertSize.convert(@virtualMemory)
      totalMemoryKb = memoryKb + virtualMemoryKb
      ConvertSize.convertUnit("#{totalMemoryKb}K", 'M')
    else
      memoryInteger = parseInt(@memory)
      # If virtualMemory is not specified, the default is to have
      # memory == swap, so for 256M of memory, we also allocate 256M of swap,
      # making total memory allocated to the box 512M.
      "#{(memoryInteger * 2)}#{this.memoryUnit()}"

  updateAttributes: (attrs, cb) ->
    self = this
    _.each attrs, (v, k, attrs) -> self[k] = v
    self.save cb

  save: (done) ->
    redisClient.hset 'aio:boxes', this.containerName(), this.encode(), (err, result) ->
      done(err)

  delete: (done) ->
    redisClient.hdel 'aio:boxes', this.containerName(), (err, res) ->
      done(err)

  configure: (dataType, data, done) ->
    if dataType == 'aio:configure:add_public_key'
      publicKey = data
      @_execShellCommand "boxer-add-public-keys",
                          [this.containerName(), publicKey],
                          sudo: true,
                          done
    else if dataType == 'aio:configure:remove_public_key'
      publicKey = data.replace(/\//g, "\\/")
      @_execShellCommand "boxer-remove-public-key",
                          [this.containerName(), publicKey],
                          sudo: true,
                          done
    else if dataType == 'aio:configure:set_env_variables'
      envVars = ( "#{key}=#{value}" for key, value of data )
      @_execShellCommand "boxer-set-env-variables",
                          [this.containerName()].concat(envVars),
                          sudo: true,
                          done
    else if dataType == 'aio:configure:remove_env_variables'
      @_execShellCommand "boxer-remove-env-variables",
                          [this.containerName()].concat(data),
                          sudo: true,
                          done
    else if dataType == 'aio:configure:change_specs'
      this.quota (err, quota) =>
        return done(new Error('Cannot retrieve box quota')) if err
        return done(new Error('Current Disk Usage Exceeds New Disk Quota')) if quota.used > ConvertSize.convert(data.diskSpace)

        @diskSpace = ConvertSize.convertUnit(data.diskSpace, 'M') if data.diskSpace

        this._stopContainer (err) =>
          return done(new Error('Cannot stop the current container')) if err
          this._changeCPUShares data, (err) =>
            return done(new Error('Cannot change CPU shares')) if err
            this._changeMemoryLimit data, (err) =>
              return done(new Error('Cannot change the memory limit')) if err
              this._changeDiskQuota (err) =>
                return done(new Error('Cannot change the disk limit')) if err
                this._startContainer (err) =>
                  return done(new Error('Cannot start the container')) if err
                  this.updateAttributes containerState: 'running', done

    else if dataType == 'aio:configure:update_auth'
      this.updateAttributes { authUsername: data.auth_username, authPassword: data.auth_password }, =>
        this._invalidateCache done

    else if dataType == 'aio:configure:update_premium'
      this.updateAttributes { premium: data.premium }, =>
        this._setPremium =>
          this._invalidateCache done

  stop: (cb) ->
    if this.valid()
      self = this
      this._stopContainer ->
        self._unmountContainer ->
          self.updateAttributes containerState: 'stopped', cb
    else
      cb(new Error('Invalid Params'))

  restart: (data, cb) ->
    if this.valid()
      self = this
      this.stop ->
        self.start data, cb
    else
      cb(new Error('Invalid Params'))

  destroy: (@done) ->
    if this.valid()
      async.waterfall [
        # stop instead of just unmount here to make sure that we can unmount
        # successfully
        (cb) => this._stopContainer (err) -> cb(err)
        (cb) => this._removeDefaultKeyPair (err) -> cb(err)
        (cb) => this._releasePortForwarding (err) -> cb(err)
        (cb) => this._unmountContainer (err) -> cb(err)
        (cb) => this._removeContainer (err) -> cb(err)
        (cb) => this._releaseResources (err) -> cb(err)
        (cb) =>
          try this.delete cb
          catch e then cb(new Error("failed to delete #{this.containerName()}: #{e}"))
      ], (err) =>
        console.log "Failed to remove #{this.containerName()} : #{err}" if err
        @done(err)
    else
      @done(new Error('Invalid Params'))

  info: (cb) ->
    if this.mountMethod() == "lvm"
      script = "lvm/boxer-info"
      args = [this.containerName()]
    else
      if this.getQuotaMethod() == "usrquota"
        args = [@disk, this.containerName(), this._uid()]
        script = "usrquota/boxer-info"
      else
        args = [@disk, this.containerName()]
        script = "boxer-info"
    this._execShellCommand script, args, sudo: true, (err, stdout, stderr) =>
      return cb(err) if err
      [lxcStatus, memoryUsageInBytes, storageUsageInKB] = stdout.split("-")

      # Returns size in MB
      cb null,
          storageUsage: parseFloat(storageUsageInKB) / 1024
          memoryUsage: parseFloat(memoryUsageInBytes) / (1024 * 1024)
          lxcStatus: lxcStatus

  quota: (cb) ->
    if this.mountMethod() == "lvm"
      script = "lvm/boxer-report-current-limit"
      args = [this.containerName()]
    else
      if this.getQuotaMethod() == "usrquota"
        args = [@disk, this._uid()]
        script = "usrquota/boxer-report-current-limit"
      else
        args = [@disk, this.containerName()]
        script = "boxer-report-current-limit"
    this._execShellCommand script, args, sudo: true, (err, stdout, stderr) =>
      return cb(err) if err

      [used, limit] = stdout.split("-")
      cb null, used: ConvertSize.convert(used), limit: ConvertSize.convert(limit)

  migrate: (cb) ->
    return cb(null) if this.mountMethod() == "lvm"
    # add 5% to storage space to take care of storage space
    diskSpace = parseInt(parseInt(@diskSpace) * 1.05)
    @selectedVG = settings.selectedVG
    args = [this.containerName(), diskSpace + "M", @disk, @aufs.toString(), @selectedVG]
    start = new Date()
    async.waterfall [
      (cb) => this._stopContainer cb
      (stdout, stderr, cb) => this._execShellCommand "boxer-migrate-to-lvm", args, sudo: true, cb
    ], (err, stdout, stderr) =>
      console.log "===> Migrate finished in: #{new Date() - start}"
      if err
        console.log "====> ERR: #{err}, stdout: #{stdout}, stderr: #{stderr}"
        return cb(err)
      this.mount = "lvm"
      this.save cb

  encode: ->
    JSON.stringify({
                    id: +@id
                    name: @name
                    ip: @ip
                    gateway: @gateway
                    interface: @interface
                    port: +@port
                    memory: @memory
                    virtualMemory: @virtualMemory
                    disk: @disk
                    diskSpace: @diskSpace
                    snapshotURL: @snapshotURL
                    containerTemplate: @containerTemplate
                    boxerId: @boxerId
                    containerState: @containerState
                    aufs: @aufs
                    swappiness: +@swappiness
                    cpuShares: +@cpuShares
                    mount: this.mountMethod()
                    quotaMethod: this.getQuotaMethod()
                    authUsername: @authUsername
                    authPassword: @authPassword
                    premium: @premium == "true" || @premium == true
                    selectedVG: @selectedVG
                  })

  @find: (containerName, cb) ->
    redisClient.hget 'aio:boxes', containerName, (err, res) ->
      if !err
        parsedBox = JSON.parse(res)
        unless parsedBox
          err = new Error("BoxNotFound: #{containerName}")
          return cb(err, null)
        box = new Box(parsedBox.id, redisStoreSettings)
        box.name = parsedBox.name
        box.ip = parsedBox.ip
        box.gateway = parsedBox.gateway
        box.interface = parsedBox.interface
        box.port = parsedBox.port
        box.memory = parsedBox.memory
        box.virtualMemory = parsedBox.virtualMemory
        box.diskSpace = parsedBox.diskSpace
        box.containerTemplate = parsedBox.containerTemplate
        box.containerState = parsedBox.containerState
        box.disk = parsedBox.disk
        box.premium = parsedBox.premium

        # if the box is an old lvm box i.e. created before selectedVG feature,
        # we assume that the box lives in boxhost volume group
        if parsedBox.selectedVG != undefined
          box.selectedVG = parsedBox.selectedVG
        else
          box.selectedVG = "boxhost"

        if parsedBox.mount != undefined
          box.mount = parsedBox.mount
        else
          box.mount = box.mountMethod()

        if parsedBox.quotaMethod != undefined
          box.quotaMethod = parsedBox.quotaMethod
        else
          box.quotaMethod = box.getQuotaMethod()

        if parsedBox.aufs != undefined
          box.aufs = parsedBox.aufs
        else
          box.aufs = false

        if parsedBox.swappiness != undefined
          box.swappiness = parsedBox.swappiness
        else
          box.swappiness = Box.SWAPPINESS

        if parsedBox.cpuShares != undefined
          box.cpuShares = parsedBox.cpuShares
        else
          box.cpuShares = Box.CPU_SHARES

        cb(err, box)
      else
        cb(err, null)

  @startAll: (done) ->
    redisClient.hkeys 'aio:boxes', (err, ids) ->
      done(err) if err

      async.map ids, Box.find, (err, boxes) ->
        startAll = (box, cb) -> if box.containerState == 'running' then box.start(null, cb) else cb()
        async.forEachSeries boxes, startAll, (err) -> done() if !err

  @configureAll: (done) ->
    redisClient.hkeys 'aio:boxes', (err, ids) ->
      done(err) if err

      async.map ids, Box.find, (err, boxes) ->
        configureAll = (box, cb) -> box._configureBox(cb)
        async.forEachSeries boxes, configureAll, (err) -> done() if !err

  # "Private" Methods
  _acquireResources: (done) ->
    console.log 'Acquiring Resources'
    ResourcePool.acquire (err, resources) =>
      if !err
        @ip = resources.ip
        @gateway = resources.gateway
        @interface = resources.interface
        @port = parseInt(resources.port)

      done(err)

  _releaseResources: (done) ->
    console.log 'Releasing Resources'
    resource =
      ip: @ip
      gateway: @gateway
      interface: @interface
      port: @port

    ResourcePool.release resource, (err) ->
      console.log "Done Releasing Resources, error: #{err}"
      done(err)

  _prepareContainer: (done) ->
    console.log 'Create Volume'
    if this.mountMethod() == "lvm"
      this._execShellCommand 'lvm/boxer-create-volume',
        [this.containerName(), @diskSpace, @selectedVG], sudo: true, done
    else
      console.log 'Setting Up Delta Container'
      this._execShellCommand 'boxer-setup-delta-container',
        [@id, this.containerName(), @containerTemplate, @disk], sudo: true, done

  _mountContainer: (done) ->
    args = [@id, this.containerName()]
    if this.mountMethod() == "lvm"
      args.push @selectedVG
      this._execShellCommand 'lvm/boxer-mount-container', args, sudo: true, done
    else
      if this.getQuotaMethod() == "usrquota"
        args.push @containerTemplate, this.getBlockLimit(), @disk, @aufs.toString(), this._uid()
        this._execShellCommand 'usrquota/boxer-mount-container', args, sudo: true, done
      else
        args.push @containerTemplate, @diskSpace, @disk, @aufs.toString()
        this._execShellCommand 'boxer-mount-container', args, sudo: true, done

  _unmountContainer: (done) ->
    console.log 'Unmounting Container'
    args = [this.containerName()]
    if this.mountMethod() == "lvm"
      this._execShellCommand 'lvm/boxer-unmount-container', args, sudo: true, done
    else
      args.push @disk
      this._execShellCommand 'boxer-unmount-container', args, sudo: true, done

  _removeContainer: (done) ->
    console.log 'Remove Container'
    args = [this.containerName()]
    if this.mountMethod() == "lvm"
      args.push @selectedVG
      this._execShellCommand 'lvm/boxer-remove-volume', args, sudo: true, done
    else
      args.push @disk
      this._execShellCommand 'boxer-cleanup-delta-container', args, sudo: true, done

  _configureBox: (done) ->
    console.log "Configuring Box: #{this._uid()} #{this._gid()}"
    args = [@id, this.containerName(), @containerTemplate,
      "#{@cpuShares}", @memory, this.totalMemory(),
      "#{@swappiness}", @ip, @gateway, @interface, this._uid(), this._gid()]

    if this.mountMethod() == "lvm"
      args.push this._cpuSet()
      this._execShellCommand 'lvm/boxer-configure-box', args, sudo: true, done
    else
      args.push @disk
      args.push this._cpuSet()
      this._execShellCommand 'boxer-configure-box', args, sudo: true, done

  _removeBoxConfig: (done) ->
    done()

  # TODO: So in development mode (if you're runnign in Vagrant)
  # you need two iptables rules for port forwarding to work correctly,
  # both of which are set in the boxer-setup-portforwarding-dev
  # I didn't know of a clean way to make it work for existing iptables rules,
  # which is why a separate script is invoked in development mode
  #
  # This needs to be ported to goboxer too
  _setUpPortForwarding: (done) ->
    script = 'boxer-setup-portforwarding'
    script = "#{script}-dev" if process.env.NODE_ENV == 'development'
    console.log "Port Forwarding Set Up: #{script}"
    this._execShellCommand script, [@ip, @port], sudo: true, done

  # TODO: So in development mode (if you're runnign in Vagrant)
  # you need two iptables rules for port forwarding to work correctly,
  # both of which are set in the boxer-setup-portforwarding-dev
  # I didn't know of a clean way to make it work for existing iptables rules,
  # which is why a separate script is invoked in development mode
  #
  # This needs to be ported to goboxer too
  _releasePortForwarding: (done) ->
    script = 'boxer-release-portforwarding'
    script = "#{script}-dev" if process.env.NODE_ENV == 'development'
    console.log "Port Forwarding Released: #{script}"
    # ignore iptables error when the rule does not exist
    this._execShellCommand script, [@ip, @port], sudo: true, (err) -> done()

  _setDefaultKeyPair: (done) ->
    console.log 'Setting default ssh key-pair'
    args = [this.containerName()]
    if this.mountMethod() == "lvm"
      this._execShellCommand 'lvm/boxer-set-default-key-pair', args, sudo: true, done
    else
      args.push @disk
      this._execShellCommand 'boxer-set-default-key-pair', args, sudo: true, done

  _removeDefaultKeyPair: (done) ->
    console.log 'Remove default ssh key pair'
    this._execShellCommand 'boxer-remove-default-key-pair',
                           [this.containerName()],
                           sudo: true
                           done

  _startContainer: (done) ->
    console.log 'Start Container'
    this._execShellCommand 'boxer-start-container',
                           [this.containerName(), @ip],
                           sudo: true,
                           done

  _stopContainer: (done) ->
    console.log 'Stop Container'
    this._execShellCommand 'boxer-stop-container',
                           [this.containerName()],
                           sudo: true,
                           done

  _savePublicKeys: (done) ->
    return done() unless @publicKeys?
    this._execShellCommand 'boxer-add-public-keys',
      [this.containerName()].concat(@publicKeys),
      sudo: true, done

  _setPremium: (done) ->
    flag = if @premium then '1' else '0'
    this._execShellCommand 'boxer-set-premium',
      [this.containerName(), flag],
      sudo: true, done

  _execShellCommand: (cmd, args, opts, done) ->
    if _.isFunction(args)
      done = args
      args = []
      opts = {}
    else if _.isFunction(opts)
      done = opts
      opts = {}

    prefix = if process.env.NODE_ENV == 'production' then '/var/apps/boxer/current/scripts/' else scriptPath
    sudo = if opts.sudo then 'sudo' else ''

    command = _.flatten([
                          sudo
                          "#{prefix}#{cmd}"
                          _.map(args, (x) -> escapeShellArg(x))
                        ]).join(' ').trim()

    console.log "Executing command #{command}"
    start = new Date()
    childProcess.exec command, timeout: 0, (err, stdout, stderr) =>
      if err
        console.log "boxer_exec_shell_command_err: #{stderr}"
        done(err, stdout, stderr)
      else
        console.log "command: #{command} took: #{+(new Date() - start)} ms"
        done(err, stdout, stderr)

  _uid: ->
    Box.UID_BASE + parseInt(@id)

  _gid: ->
    Box.UID_BASE + parseInt(@id)

  _cpuSet: ->
    cores = os.cpus().length
    switch cores
      when 1 then '0'
      else [1..cores-1].join(",")

  _changeCPUShares: (specs, done) ->
    return done() unless specs && specs.cpuShares

    @cpuShares = specs.cpuShares
    this._execShellCommand "boxer-change-cpu-shares",
      [this.containerName(), @cpuShares],
      sudo: true,
      done

  _changeMemoryLimit: (specs, done) ->
    return done() unless specs && (specs.memory || specs.virtualMemory)

    @memory = specs.memory
    @virtualMemory = specs.virtualMemory || @memory
    this._execShellCommand "boxer-change-memory-limit",
      [this.containerName(), @memory, this.totalMemory()],
      sudo: true,
      done

  _changeDiskQuota: (done) ->
    if this.mountMethod() == "lvm"
      args = [this.containerName(), @diskSpace, @selectedVG]
      this._execShellCommand "lvm/boxer-change-disk-limit", args, sudo: true, done
    else
      if this.getQuotaMethod() == "usrquota"
        args = [@disk, this._uid(), this.getBlockLimit()]
        this._execShellCommand "usrquota/boxer-change-disk-limit", args, sudo: true, done
      else
        args = [@disk, this.containerName(), @diskSpace]
        this._execShellCommand "boxer-change-disk-limit", args, sudo: true, done

  _invalidateCache: (done) ->
    options =
      hostname: settings.cartmanHost
      port: settings.cartmanPort
      path: "/invalidate_cache?id=#{this.containerName()}"

    http.get options, ->
      done()
