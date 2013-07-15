AutoAdvancingStateMachine = require './auto_advancing_state_machine'
ConvertSize = require './convert_size'
ResourcePool = require './resource_pool'
settings = require '../../config/settings'
escapeShellArg = require('./utils').escapeShellArg
redisStoreSettings = require('../../config/settings').redisStore
redisClient = require('./utils').initRedisClientWith(redisStoreSettings, "localStore")
scriptPath = __dirname.replace('app/lib', 'scripts/')
childProcess = require 'child_process'
initAirbrakeClient = require('./utils').initAirbrakeClient
s3 = require './s3'
fs = require 'fs'

async = require 'async'
_ = require 'underscore'

module.exports = class Box extends AutoAdvancingStateMachine
  states: [
    { name: 'initialized',         onAdvance: '_acquireResources',    onRollback: '_notifyRollback' }
    { name: 'resourcesAcquired',   onAdvance: '_setupDeltaContainer', onRollback: '_releaseResources' }
    { name: 'containerPrepared',   onAdvance: '_mountContainer',      onRollback: '_cleanupDeltaContainer' }
    { name: 'containerMounted',    onAdvance: '_configureBox',        onRollback: '_unmountContainer' }
    { name: 'boxConfigured',       onAdvance: '_setUpPortForwarding', onRollback: '_removeBoxConfig' }
    { name: 'portForwardingSetUp', onAdvance: '_setDefaultKeyPair',   onRollback: '_releasePortForwarding' }
    { name: 'setupDefaultKeyPair', onAdvance: 'save',                 onRollback: '_removeDefaultKeyPair' }
    { name: 'boxSaved',            onAdvance: '_notifySuccess',       onRollback: 'delete' }
  ]

  @UID_BASE = 15000

  constructor: (@id) ->
    @ip = @gateway = @interface = @port = @boxerCallback = null
    @containerState = 'stopped'
    @name = @containerTemplate = null
    @memory = @diskSpace = @publicKeys = @snapshotURL = null
    @disk = null
    @boxerId = null
    @airbreakClient = initAirbrakeClient(settings.airbrakeAPIKey)
    super

  containerName: -> "#{@name}-#{@id}"

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

  create: (@successCallback, @rollbackCallback) ->
    if this.valid()
      this.startStateMachine()
    else
      @rollbackCallback(new Error('Invalid Params'))

  start: (cb) ->
    if this.valid()
      self = this
      self._mountContainer ->
        self._startContainer ->
          self.updateAttributes containerState: 'running', cb
    else
      cb(new Error('Invalid Params'))

  memoryUnit: ->
    ConvertSize.unit @memory

  totalMemory: ->
    if @memory
      memoryInteger = parseInt(@memory)
      # totalMemory is the sum of the memory allocated to the box,
      # plus twice the memory allocated for swap, so for 256M, the swap
      # memory allocated will be 512M, making the total memory allocated to the box
      # 768M
      #
      # This is used for the lxc.cgroup.memory.memsw.limit_in_bytes setting in LXC
      "#{(memoryInteger * 3)}#{this.memoryUnit()}"
    else
      null

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

        @memory = data.memory if data.memory
        @diskSpace = ConvertSize.convertUnit(data.diskSpace, "M") if data.diskSpace
        this._stopContainer (err) =>
          return done(new Error('Cannot stop the current container')) if err
          this._changeMemoryLimit (err) =>
            return done(new Error('Cannot change the memory limit')) if err
            this._changeDiskQuota (err) =>
              return done(new Error('Cannot change the disk limit')) if err
              this._startContainer (err) =>
                return done(new Error('Cannot start the container')) if err
                this.updateAttributes containerState: 'running', done

  stop: (cb) ->
    if this.valid()
      self = this
      this._stopContainer ->
        self._unmountContainer ->
          self.updateAttributes containerState: 'stopped', cb
    else
      cb(new Error('Invalid Params'))

  restart: (cb) ->
    if this.valid()
      self = this
      this.stop ->
        self.start cb
    else
      cb(new Error('Invalid Params'))

  destroy: (@rollbackCallback) ->
    if this.valid()
      this.rollbackStateMachine()
    else
      cb(new Error('Invalid Params'))

  info: (cb) ->
    this._execShellCommand "boxer-info", [@disk, this.containerName()], sudo: true, (err, stdout, stderr) =>
      return cb(err) if err
      [lxcStatus, memoryUsageInBytes, storageUsageInKB] = stdout.split("-")

      # Returns size in MB
      cb null,
          storageUsage: parseFloat(storageUsageInKB) / 1024
          memoryUsage: parseFloat(memoryUsageInBytes) / (1024 * 1024)
          lxcStatus: lxcStatus

  quota: (cb) ->
    this._execShellCommand "boxer-report-current-limit", [@disk, this.containerName()], sudo: true, (err, stdout, stderr) =>
      return cb(err) if err
      [used, limit] = stdout.split("-")
      cb null, used: ConvertSize.convert(used), limit: ConvertSize.convert(limit)

  snapshot: (cb) ->
    if this.valid()
      snapshotName = "#{this.containerName()}-#{+new Date()}.tar.gz"
      snapshotUrl = "s3://#{settings.awsRegion}/#{settings.awsBucket}/#{snapshotName}"
      snapshotPath =  @disk + "/" + snapshotName
      this._stopContainer =>
        finishCompress = =>
          stream = fs.createReadStream snapshotPath
          writeParams = { Bucket: settings.awsBucket, Key: snapshotName, Body: stream }
          s3.client.putObject writeParams, =>
            this._execShellCommand 'boxer-cleanup-local-tar',
              [@disk, snapshotName],
              sudo: true,
              -> cb null, snapshotUrl
        this._execShellCommand 'boxer-tar-delta-container',
                                [@disk, this.containerName(), snapshotName],
                                sudo: true,
                                finishCompress
    else
      cb(new Error('Invalid Params'))

  encode: ->
    JSON.stringify({
                    id: @id
                    name: @name
                    ip: @ip
                    gateway: @gateway
                    interface: @interface
                    port: @port
                    memory: @memory
                    disk: @disk
                    diskSpace: @diskSpace
                    snapshotURL: @snapshotURL
                    containerTemplate: @containerTemplate
                    boxerId: @boxerId
                    containerState: @containerState
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
        box.diskSpace = parsedBox.diskSpace
        box.containerTemplate = parsedBox.containerTemplate
        box.containerState = parsedBox.containerState
        box.disk = parsedBox.disk

        cb(err, box)
      else
        cb(err, null)

  @startAll: (done) ->
    redisClient.hkeys 'aio:boxes', (err, ids) ->
      done(err) if err

      async.map ids, Box.find, (err, boxes) ->
        startAll = (box, cb) -> if box.containerState == 'running' then box.start(cb) else cb()
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

  _setupDeltaContainer: (done) ->
    console.log 'Setting Up Delta Container'
    this._execShellCommand 'boxer-setup-delta-container',
                           [@id, this.containerName(), @containerTemplate, @disk],
                           sudo: true,
                           done

  _mountContainer: (done) ->
    console.log 'Mounting Container'
    this._execShellCommand 'boxer-mount-container',
                           [@id, this.containerName(), @containerTemplate, @diskSpace, @disk],
                           sudo: true,
                           done

  _unmountContainer: (done) ->
    console.log 'Unmounting Container'
    this._execShellCommand 'boxer-unmount-container',
                           [this.containerName(), @disk],
                           sudo: true,
                           done

  _cleanupDeltaContainer: (done) ->
    console.log 'Cleaning Up Delta Container'
    this._execShellCommand 'boxer-cleanup-delta-container',
                           [this.containerName(), @disk],
                           sudo: true,
                           done

  _configureBox: (done) ->
    console.log "Configuring Box: #{this._uid()} #{this._gid()}"
    this._execShellCommand 'boxer-configure-box',
                           [@id, this.containerName(), @containerTemplate, @memory, this.totalMemory(), @ip, @gateway, @interface, this._uid(), this._gid(), @disk],
                           sudo: true,
                           done

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

    this._execShellCommand script,
                           [@ip, @port],
                           sudo: true,
                           done

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

    this._execShellCommand script,
                           [@ip, @port],
                           sudo: true,
                           done

  _setDefaultKeyPair: (done) ->
    console.log 'Setting default ssh key-pair'
    this._execShellCommand 'boxer-set-default-key-pair',
                            [this.containerName(), @disk],
                            sudo: true
                            done

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

  _notifySuccess: (done) ->
    if @publicKeys?
      self = this
      this._execShellCommand 'boxer-add-public-keys',
                             [this.containerName()].concat(@publicKeys),
                             sudo: true, ->
                               self.successCallback?(null)
                               delete self.successCallback
                               done()
    else
      @successCallback?(null)
      delete @successCallback
      done()

  _notifyRollback: (done) ->
    @rollbackCallback?(null)
    delete @rollbackCallback
    done()

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

  _changeMemoryLimit: (done) ->
    this._execShellCommand "boxer-change-memory-limit",
      [this.containerName(), @memory, this.totalMemory()],
      sudo: true,
      done

  _changeDiskQuota: (done) ->
    this._execShellCommand "boxer-change-disk-limit",
      [@disk, this.containerName(), @diskSpace],
      sudo: true,
      done
