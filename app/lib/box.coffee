AutoAdvancingStateMachine = require './auto_advancing_state_machine'
ResourcePool = require './resource_pool'
settings = require '../../config/settings'
escapeShellArg = require('./utils').escapeShellArg
initRedisClientWith = require('./utils').initRedisClientWith
scriptPath = __dirname.replace('app/lib', 'scripts/')
childProcess = require 'child_process'
logger = require './logger'
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

  constructor: (@id, redisStoreSettings) ->
    @ip = @port = @boxerCallback = null
    @name = @containerTemplate = @lxcRoot = null
    @memory = @diskSpace = @publicKeys = @snapshotURL = null
    @boxerId = null
    # Setup the Redis client
    @redisClient = initRedisClientWith(redisStoreSettings) if redisStoreSettings?
    super

  valid: (opts) ->
    attributesToValidate = []
    self = this

    if opts?.onCreate?
      attributesToValidate = ['id', 'name', 'containerTemplate', 'memory', 'diskSpace', 'lxcRoot']
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
      this._mountContainer =>
        this._startContainer cb
    else
      cb(new Error('Invalid Params'))

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
                          [@lxcRoot, @name, publicKey],
                          sudo: true,
                          done
    else if dataType == 'aio:configure:remove_public_key'
      publicKey = data.replace(/\//g, "\\/")

      @_execShellCommand "boxer-remove-public-key",
                          [@lxcRoot, @name, publicKey],
                          sudo: true,
                          done
    else if dataType == 'aio:configure:set_env_variables'
      envVars = ( "#{key}=#{value}" for key, value of data )
      @_execShellCommand "boxer-set-env-variables",
                          [@lxcRoot, @name].concat(envVars),
                          sudo: true,
                          done
    else if dataType == 'aio:configure:remove_env_variables'
      @_execShellCommand "boxer-remove-env-variables",
                          [@lxcRoot, @name].concat(data),
                          sudo: true,
                          done

  stop: (cb) ->
    if this.valid()
      self = this
      this._stopContainer ->
        self._unmountContainer cb
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
                    port: @port
                    memory: @memory
                    diskSpace: @diskSpace
                    snapshotURL: @snapshotURL
                    containerTemplate: @containerTemplate
                    boxerId: @boxerId
                  })

  @find: (name, redisStoreSettings, cb) ->
    redisClient = initRedisClientWith(redisStoreSettings)
    redisClient.hget 'aio:boxes', name, (err, res) ->
      if !err
        parsedBox = JSON.parse(res)
        box = new Box(parsedBox.id, redisStoreSettings)
        box.name = parsedBox.name
        box.ip = parsedBox.ip
        box.port = parsedBox.port
        box.memory = parsedBox.memory
        box.diskSpace = parsedBox.diskSpace
        box.containerTemplate = parsedBox.containerTemplate

        cb(err, box)
      else
        cb(err, null)

  # "Private" Methods
  _acquireResources: (done) ->
    logger.info 'Acquiring Resources'
    ResourcePool.acquire (err, resources) =>
      if !err
        @ip = resources.ip
        @port = parseInt(resources.port)

      done(err)

  _releaseResources: (done) ->
    logger.info 'Releasing Resources'
    resources = {
                  ip: @ip
                  port: @port
                }

    ResourcePool.release resources, (err) ->
      logger.info "Done Releasing Resources #{err}"
      done(err)

  _setupDeltaContainer: (done) ->
    logger.info 'Setting Up Delta Container'
    this._execShellCommand 'boxer-setup-delta-container',
                           [@id, @lxcRoot, @name, @containerTemplate],
                           sudo: true,
                           done

  _mountContainer: (done) ->
    logger.info 'Mounting Container'
    this._execShellCommand 'boxer-mount-container',
                           [@id, @lxcRoot, @name, @containerTemplate, @diskSpace],
                           sudo: true,
                           done

  _unmountContainer: (done) ->
    logger.info 'Unmounting Container'
    this._execShellCommand 'boxer-unmount-container',
                           [@lxcRoot, @name],
                           sudo: true,
                           done

  _cleanupDeltaContainer: (done) ->
    logger.info 'Cleaning Up Delta Container'
    this._execShellCommand 'boxer-cleanup-delta-container',
                           [@lxcRoot, @name],
                           sudo: true,
                           done

  _configureBox: (done) ->
    logger.info 'Configuring Box'
    this._execShellCommand 'boxer-configure-box',
                           [@lxcRoot, @name, @containerTemplate, @ip]
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
                            [@lxcRoot, @name],
                            sudo: true
                            done

  _removeDefaultKeyPair: (done) ->
    logger.info 'Remove default ssh key pair'
    this._execShellCommand 'boxer-remove-default-key-pair',
                           [@lxcRoot, @name],
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
                             [@lxcRoot, @name].concat(@publicKeys),
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
        logger.info "stderr --> #{stderr}"
      done(err)
