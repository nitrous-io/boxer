AutoAdvancingStateMachine = require './auto_advancing_state_machine'
ResourcePool = require './resource_pool'
settings = require '../../config/settings'
escapeShellArg = require('./utils').escapeShellArg
initRedisClientWith = require('./utils').initRedisClientWith
scriptPath = __dirname.replace('app/lib', 'scripts/')
childProcess = require 'child_process'
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
    @hostName = @containerTemplate = @lxcRoot = null
    @memory = @diskSpace = @publicKeys = @snapshotURL = null
    # Setup the Redis client
    @redisClient = initRedisClientWith(redisStoreSettings)

    super

  create: (@successCallback, @rollbackCallback) ->
    this.startStateMachine()

  start: (cb) ->
    this._startContainer cb

  save: (done) ->
    @redisClient.hset 'aio.boxes', @id, this.encode(), (err, result) ->
      done(err)

  delete: (done) ->
    @redisClient.hdel 'aio.boxes', @id, (err, res) ->
      done(err)

  stop: (cb) ->
    this._stopContainer cb

  destroy: (@rollbackCallback) ->
    this.rollbackStateMachine()

  encode: ->
    JSON.stringify({
                    id: @id
                    hostName: @hostName
                    ip: @ip
                    port: @port
                    memory: @memory
                    diskSpace: @diskSpace
                    snapshotURL: @snapshotURL
                    containerTemplate: @containerTemplate
                  })

  @find: (id, redisStoreSettings, cb) ->
    redisClient = initRedisClientWith(redisStoreSettings)
    redisClient.hget 'aio.boxes', id, (err, res) ->
      if !err
        parsedBox = JSON.parse(res)
        box = new Box(id, redisStoreSettings)
        box.hostName = parsedBox.hostName
        box.ip = parsedBox.ip
        box.port = parsedBox.port
        box.memory = parsedBox.memory
        box.diskSpace = parsedBox.diskSpace

        cb(err, box)
      else
        cb(err, null)

  # "Private" Methods
  _acquireResources: (done) ->
    console.log "Acquiring Resources"
    ResourcePool.acquire (err, resources) =>
      if !err
        @ip = "192.168.254.#{resources.ip}"
        @port = parseInt(resources.port)
      done()

  _releaseResources: (done) ->
    console.log "Releasing Resources"
    octet = _.last(@ip.split('.'))
    resources = {
                  ip: octet
                  port: @port
                }

    ResourcePool.release resources, (err) ->
      console.log "Done Releasing Resources #{err}"
      done(err)

  _mountContainer: (done) ->
    console.log "Mounting Container"
    this._execShellCommand "boxer-mount-container",
                           [@lxcRoot, @hostName, @containerTemplate],
                           sudo: true,
                           done

  _unmountContainer: (done) ->
    console.log "Unmounting Container"
    this._execShellCommand "boxer-unmount-container",
                           [@lxcRoot, @hostName],
                           sudo: true,
                           done

  _configureBox: (done) ->
    console.log "Configuring Box"
    this._execShellCommand "boxer-configure-box",
                           [@lxcRoot, @hostName, @containerTemplate, @ip]
                           sudo: true,
                           done

  _removeBoxConfig: (done) ->
    done()

  _setUpPortForwarding: (done) ->
    console.log "Port Forwarding Set Up"
    this._execShellCommand "boxer-setup-portforwarding",
                           [@ip, @port],
                           sudo: true,
                           done

  _releasePortForwarding: (done) ->
    console.log "Port Forwarding Released"
    this._execShellCommand "boxer-release-portforwarding",
                           [@ip, @port],
                           sudo: true,
                           done

  _startContainer: (done) ->
    console.log "Start Container"
    this._execShellCommand "boxer-start-container",
                           [@hostName, @ip],
                           sudo: true,
                           done

  _stopContainer: (done) ->
    console.log "Stop Container"
    this._execShellCommand "boxer-stop-container",
                           [@hostName],
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

    console.log "Executing command #{command}"
    childProcess.exec command, timeout: 0, (err, stdout, stderr) ->
      if err
        console.log "stderr --> #{stderr}"
      done(err)
