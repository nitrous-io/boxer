AutoAdvancingStateMachine = require './auto_advancing_state_machine'
ResourcePool = require './resource_pool'
settings = require '../../config/settings'
escapeShellArg = require('./utils').escapeShellArg
initRedisClientWith = require('./utils').initRedisClientWith
redisStoreSettings = require('../../config/settings').redisStore
scriptPath = __dirname.replace('app/lib', 'scripts/')
childProcess = require 'child_process'
logger = require './logger'

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

  constructor: (@id) ->
    @ip = @gateway = @interface = @port = @boxerCallback = null
    @containerState = 'stopped'
    @name = @containerTemplate = null
    @memory = @diskSpace = @publicKeys = @snapshotURL = null
    @boxerId = null
    # Setup the Redis client
    @redisClient = initRedisClientWith(redisStoreSettings)
    super

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

  updateAttributes: (attrs, cb) ->
    self = this
    _.each attrs, (v, k, attrs) -> self[k] = v
    self.save cb

  save: (done) ->
    @redisClient.hset 'aio:boxes', @name, this.encode(), (err, result) ->
      done(err)

  delete: (done) ->
    @redisClient.hdel 'aio:boxes', @name, (err, res) ->
      done(err)

  configure: (dataType, data, done) ->
    if dataType == 'aio:configure:add_public_key'
      publicKey = data

      @_execShellCommand "boxer-add-public-keys",
                          [@name, publicKey],
                          sudo: true,
                          done
    else if dataType == 'aio:configure:remove_public_key'
      publicKey = data.replace(/\//g, "\\/")

      @_execShellCommand "boxer-remove-public-key",
                          [@name, publicKey],
                          sudo: true,
                          done
    else if dataType == 'aio:configure:set_env_variables'
      envVars = ( "#{key}=#{value}" for key, value of data )
      @_execShellCommand "boxer-set-env-variables",
                          [@name].concat(envVars),
                          sudo: true,
                          done
    else if dataType == 'aio:configure:remove_env_variables'
      @_execShellCommand "boxer-remove-env-variables",
                          [@name].concat(data),
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

  @find: (name, cb) ->
    redisClient = initRedisClientWith(redisStoreSettings)
    redisClient.hget 'aio:boxes', name, (err, res) ->
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
    redisClient = initRedisClientWith(redisStoreSettings)
    redisClient.hkeys 'aio:boxes', (err, ids) ->
      done(err) if err

      async.map ids, Box.find, (err, boxes) ->
        startAll = (box, cb) -> if box.containerState == 'running' then box.start(cb) else cb()
        async.forEachSeries boxes, startAll, (err) -> done() if !err

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
    this._execShellCommand 'boxer-setup-delta-container',
                           [@id, @name, @containerTemplate],
                           sudo: true,
                           done

  _mountContainer: (done) ->
    logger.info 'Mounting Container'
    this._execShellCommand 'boxer-mount-container',
                           [@id, @name, @containerTemplate, @diskSpace],
                           sudo: true,
                           done

  _unmountContainer: (done) ->
    logger.info 'Unmounting Container'
    this._execShellCommand 'boxer-unmount-container',
                           [@name],
                           sudo: true,
                           done

  _cleanupDeltaContainer: (done) ->
    logger.info 'Cleaning Up Delta Container'
    this._execShellCommand 'boxer-cleanup-delta-container',
                           [@name],
                           sudo: true,
                           done

  _configureBox: (done) ->
    logger.info 'Configuring Box'
    this._execShellCommand 'boxer-configure-box',
                           [@name, @containerTemplate, @ip, @gateway, @interface],
                           sudo: true,
                           done

  _removeBoxConfig: (done) ->
    done()

  _setUpPortForwarding: (done) ->
    logger.info 'Port Forwarding Set Up'
    this._execShellCommand 'boxer-setup-portforwarding',
                           [@ip, @port],
                           sudo: true,
                           done

  _releasePortForwarding: (done) ->
    logger.info 'Port Forwarding Released'
    this._execShellCommand 'boxer-release-portforwarding',
                           [@ip, @port],
                           sudo: true,
                           done

  _setDefaultKeyPair: (done) ->
    logger.info 'Setting default ssh key-pair'
    this._execShellCommand 'boxer-set-default-key-pair',
                            [@name],
                            sudo: true
                            done

  _removeDefaultKeyPair: (done) ->
    logger.info 'Remove default ssh key pair'
    this._execShellCommand 'boxer-remove-default-key-pair',
                           [@name],
                           sudo: true
                           done

  _startContainer: (done) ->
    logger.info 'Start Container'
    this._execShellCommand 'boxer-start-container',
                           [@name, @ip],
                           sudo: true,
                           done

  _stopContainer: (done) ->
    logger.info 'Stop Container'
    this._execShellCommand 'boxer-stop-container',
                           [@name],
                           sudo: true,
                           done

  _notifySuccess: (done) ->
    if @publicKeys?
      self = this
      this._execShellCommand 'boxer-add-public-keys',
                             [@name].concat(@publicKeys),
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

    logger.info "Executing command #{command}"
    childProcess.exec command, timeout: 0, (err, stdout, stderr) ->
      if err
        logger.info "boxer_exec_shell_command_err: #{stderr}"
        throw err
      done(err)
