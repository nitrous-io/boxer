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
    { name: 'resourcesAcquired',   onAdvance: '_mountContainer',      onRollback: '_releaseResources' }
    { name: 'containerMounted',    onAdvance: '_configureBox',        onRollback: '_unmountContainer' }
    { name: 'boxConfigured',       onAdvance: '_setUpPortForwarding', onRollback: '_removeBoxConfig' }
    { name: 'portForwardingSetUp', onAdvance: '_startContainer',      onRollback: '_releasePortForwarding' }
    { name: 'containerStarted',    onAdvance: 'save',                 onRollback: '_stopContainer' }
    { name: 'boxSaved',            onAdvance: '_notifySuccess',       onRollback: 'delete' }
  ]

  constructor: (@id, redisStoreSettings) ->
    @ip = @port = @boxerCallback = null
    @name = @containerTemplate = @lxcRoot = null
    @memory = @diskSpace = @publicKeys = @snapshotURL = null
    @boxerId = @hostUrl = null
    # Setup the Redis client
    @redisClient = initRedisClientWith(redisStoreSettings)

    super

  create: (@successCallback, @rollbackCallback) ->
    this.startStateMachine()

  start: (cb) ->
    this._startContainer cb

  save: (done) ->
    @redisClient.hset 'aio.boxes', @name, this.encode(), (err, result) ->
      done(err)

  delete: (done) ->
    @redisClient.hdel 'aio.boxes', @name, (err, res) ->
      done(err)

  configure: (dataType, data, done) ->
    self = this
    if dataType == 'aio.configure.add_public_key'
      username = data.username
      publicKey = data.publicKey.replace("/", "\\/")

      self._execShellCommand "boxer-add-public-key",
                             [@lxcRoot, @name, username, publicKey],
                             sudo: true,
                             done
    else if dataType == 'aio.configure.remove_public_key'
      username = data.username
      publicKey = data.publicKey.replace("/", "\\/")

      self._execShellCommand "boxer-remove-public-key",
                             [@lxcRoot, @name, username, publicKey],
                             sudo: true,
                             done

  stop: (cb) ->
    this._stopContainer cb

  destroy: (@rollbackCallback) ->
    this.rollbackStateMachine()

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
                    hostUrl: @hostUrl
                  })

  @find: (name, redisStoreSettings, cb) ->
    redisClient = initRedisClientWith(redisStoreSettings)
    redisClient.hget 'aio.boxes', name, (err, res) ->
      if !err
        parsedBox = JSON.parse(res)
        box = new Box(parsedBox.id, redisStoreSettings)
        box.name = parsedBox.name
        box.ip = parsedBox.ip
        box.port = parsedBox.port
        box.memory = parsedBox.memory
        box.diskSpace = parsedBox.diskSpace

        cb(err, box)
      else
        cb(err, null)

  # "Private" Methods
  _acquireResources: (done) ->
    logger.debug "Acquiring Resources"
    ResourcePool.acquire (err, resources) =>
      if !err
        @ip = "192.168.254.#{resources.ip}"
        @port = parseInt(resources.port)
      done()

  _releaseResources: (done) ->
    logger.debug "Releasing Resources"
    octet = _.last(@ip.split('.'))
    resources = {
                  ip: octet
                  port: @port
                }

    ResourcePool.release resources, (err) ->
      logger.debug "Done Releasing Resources #{err}"
      done(err)

  _mountContainer: (done) ->
    logger.debug "Mounting Container"
    this._execShellCommand "boxer-mount-container",
                           [@lxcRoot, @name, @containerTemplate],
                           sudo: true,
                           done

  _unmountContainer: (done) ->
    logger.debug "Unmounting Container"
    this._execShellCommand "boxer-unmount-container",
                           [@lxcRoot, @name],
                           sudo: true,
                           done

  _configureBox: (done) ->
    logger.debug "Configuring Box"
    this._execShellCommand "boxer-configure-box",
                           [@lxcRoot, @name, @containerTemplate, @ip]
                           sudo: true,
                           done

  _removeBoxConfig: (done) ->
    done()

  _setUpPortForwarding: (done) ->
    logger.debug "Port Forwarding Set Up"
    this._execShellCommand "boxer-setup-portforwarding",
                           [@ip, @port],
                           sudo: true,
                           done

  _releasePortForwarding: (done) ->
    logger.debug "Port Forwarding Released"
    this._execShellCommand "boxer-release-portforwarding",
                           [@ip, @port],
                           sudo: true,
                           done

  _startContainer: (done) ->
    logger.debug "Start Container"
    this._execShellCommand "boxer-start-container",
                           [@name, @ip],
                           sudo: true,
                           done

  _stopContainer: (done) ->
    logger.debug "Stop Container"
    this._execShellCommand "boxer-stop-container",
                           [@name],
                           sudo: true,
                           done

  _notifySuccess: (done) ->
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

    prefix = if opts.prefix then "#{opts.prefix}/".replace(/\/{2,}$/, '/') else scriptPath
    sudo = if opts.sudo then 'sudo' else ''

    command = _.flatten([
                          sudo
                          "#{prefix}#{cmd}"
                          _.map(args, (x) -> escapeShellArg(x))
                        ]).join(' ').trim()

    logger.debug "Executing command #{command}"
    childProcess.exec command, timeout: 0, (err, stdout, stderr) ->
      if err
        logger.debug "stderr --> #{stderr}"
      done(err)
