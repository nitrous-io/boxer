AutoAdvancingStateMachine = require './auto_advancing_state_machine'
ResourcePool = require './resource_pool'
settings = require '../../config/settings'
{ execShellCommand  } = require './utils'
redisStoreSettings = require('../../config/settings').redisStore
redisClient = require('./utils').initRedisClientWith(redisStoreSettings)
logger = require './logger'
s3 = require './s3'
fs = require 'fs'
url = require 'url'

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
    @boxerId = null
    super

  containerName: -> "#{@name}-#{@id}"

  valid: (opts) ->
    attributesToValidate = []
    self = this

    if opts?.onCreate?
      attributesToValidate = ['id', 'name', 'containerTemplate', 'memory', 'diskSpace']
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
    if ! (memoryUnit = @memory?.match(/\d+([A-Z])/)?[1])
      ''
    else
      memoryUnit

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

      execShellCommand "boxer-add-public-keys",
                        [this.containerName(), publicKey],
                        sudo: true,
                        done
    else if dataType == 'aio:configure:remove_public_key'
      publicKey = data.replace(/\//g, "\\/")
      execShellCommand "boxer-remove-public-key",
                        [this.containerName(), publicKey],
                        sudo: true,
                        done
    else if dataType == 'aio:configure:set_env_variables'
      envVars = ( "#{key}=#{value}" for key, value of data )
      execShellCommand "boxer-set-env-variables",
                        [this.containerName()].concat(envVars),
                        sudo: true,
                        done
    else if dataType == 'aio:configure:remove_env_variables'
      execShellCommand "boxer-remove-env-variables",
                        [this.containerName()].concat(data),
                        sudo: true,
                        done

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

  snapshot: (name, done) ->
    return done(new Error('Invalid Params')) unless this.valid()
    snapshotName = "#{name}-#{+new Date()}"
    snapshotTarFile = "#{snapshotName}.tar.gz"
    snapshotUrl = "s3://#{settings.awsBucket}/#{snapshotTarFile}"
    snapshotPath = "/var/lib/lxc/#{snapshotTarFile}"

    uploadSnapshot = (cb) ->
      stream = fs.createReadStream snapshotPath
      writeParams = { Bucket: settings.awsBucket, Key: snapshotTarFile, Body: stream }
      s3.client.putObject writeParams, (err) -> cb(err)

    async.waterfall [
      (cb) => this.stop cb
      (cb) => this._compressDeltaContainer snapshotTarFile, cb
      (cb) => uploadSnapshot cb
      (cb) => fs.unlink snapshotPath, cb
      (cb) => this.start cb
    ], (err) -> done(err, snapshotUrl)

  restoreSnapshot: (snapshotUrl, done) ->
    return done(new Error('Invalid Params')) unless this.valid()
    snapshotKey = url.parse(snapshotUrl).path.replace('/', '')
    snapshotFile = "/tmp/#{snapshotKey}"
    getParams = { Bucket: settings.awsBucket, Key: snapshotKey }

    async.waterfall [
      (cb) -> s3.client.getObject getParams, cb
      (data, cb) -> fs.writeFile snapshotFile, data.Body, cb
      (cb) => this.stop cb
      (cb) => this._restoreDeltaContainer snapshotFile, cb
      (cb) => this.start cb
    ], done

  encode: ->
    JSON.stringify({
                    id: @id
                    name: @name
                    ip: @ip
                    gateway: @gateway
                    interface: @interface
                    port: @port
                    memory: @memory
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
    logger.info 'Acquiring Resources'
    ResourcePool.acquire (err, resources) =>
      if !err
        @ip = resources.ip
        @gateway = resources.gateway
        @interface = resources.interface
        @port = parseInt(resources.port)

      done(err)

  _releaseResources: (done) ->
    logger.info 'Releasing Resources'
    resource =
      ip: @ip
      gateway: @gateway
      interface: @interface
      port: @port

    ResourcePool.release resource, (err) ->
      logger.info "Done Releasing Resources #{err}"
      done(err)

  _setupDeltaContainer: (done) ->
    logger.info 'Setting Up Delta Container'
    if @snapshotURL
      snapshotKey = url.parse(@snapshotURL).path.replace('/', '')
      snapshotFile = "/tmp/#{snapshotKey}"
      getParams = { Bucket: settings.awsBucket, Key: snapshotKey }

      async.waterfall [
        (cb) -> s3.client.getObject getParams, cb
        (data, cb) -> fs.writeFile snapshotFile, data.Body, cb
        (cb) =>
          execShellCommand 'boxer-setup-delta-container',
                            [@id, this.containerName(), snapshotFile],
                            sudo: true,
                            cb
      ], done
    else
      dataPath = "/var/lib/lxc/#{@containerTemplate}.tar.gz"
      execShellCommand 'boxer-setup-delta-container',
                        [@id, this.containerName(), dataPath],
                        sudo: true,
                        done

  _compressDeltaContainer: (fileName, done) ->
    logger.info 'Compressing Delta Container'
    execShellCommand 'boxer-tar-delta-container',
                      [this.containerName(), fileName],
                      sudo: true,
                      done

  _restoreDeltaContainer: (snapshotFile, done) ->
    logger.info 'Restoring Delta Container'
    execShellCommand 'boxer-restore-delta-container',
                      [@id, this.containerName(), snapshotFile],
                      sudo: true,
                      done

  _mountContainer: (done) ->
    logger.info 'Mounting Container'
    execShellCommand 'boxer-mount-container',
                      [@id, this.containerName(), @diskSpace],
                      sudo: true,
                      done

  _unmountContainer: (done) ->
    logger.info 'Unmounting Container'
    execShellCommand 'boxer-unmount-container',
                      [this.containerName()],
                      sudo: true,
                      done

  _cleanupDeltaContainer: (done) ->
    logger.info 'Cleaning Up Delta Container'
    execShellCommand 'boxer-cleanup-delta-container',
                      [this.containerName()],
                      sudo: true,
                      done

  _configureBox: (done) ->
    logger.info "Configuring Box: #{this._uid()} #{this._gid()}"
    execShellCommand 'boxer-configure-box',
                      [@id, this.containerName(), @memory, this.totalMemory(), @ip, @gateway, @interface, this._uid(), this._gid()],
                      sudo: true,
                      done

  _removeBoxConfig: (done) ->
    done()

  _setUpPortForwarding: (done) ->
    logger.info 'Port Forwarding Set Up'
    execShellCommand 'boxer-setup-portforwarding',
                      [@ip, @port],
                      sudo: true,
                      done

  _releasePortForwarding: (done) ->
    logger.info 'Port Forwarding Released'
    execShellCommand 'boxer-release-portforwarding',
                      [@ip, @port],
                      sudo: true,
                      done

  _setDefaultKeyPair: (done) ->
    logger.info 'Setting default ssh key-pair'
    execShellCommand 'boxer-set-default-key-pair',
                      [this.containerName()],
                      sudo: true
                      done

  _removeDefaultKeyPair: (done) ->
    logger.info 'Remove default ssh key pair'
    execShellCommand 'boxer-remove-default-key-pair',
                      [this.containerName()],
                      sudo: true
                      done

  _startContainer: (done) ->
    logger.info 'Start Container'
    execShellCommand 'boxer-start-container',
                      [this.containerName(), @ip],
                      sudo: true,
                      done

  _stopContainer: (done) ->
    logger.info 'Stop Container'
    execShellCommand 'boxer-stop-container',
                      [this.containerName()],
                      sudo: true,
                      done

  _notifySuccess: (done) ->
    if @publicKeys?
      self = this
      execShellCommand 'boxer-add-public-keys',
                        [this.containerName()].concat(@publicKeys),
                        sudo: true,
                        ->
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

  _uid: ->
    Box.UID_BASE + parseInt(@id)

  _gid: ->
    Box.UID_BASE + parseInt(@id)
