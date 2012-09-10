AutoAdvancingStateMachine = require './auto_advancing_state_machine'
ResourcePool = require './resource_pool'
settings = require '../../config/settings'
childProcess = require 'child_process'
escapeShellArg = require('./utils').escapeShellArg
scriptPath = __dirname.replace('app/lib', 'scripts/')
_ = require 'underscore'

module.exports = class Box extends AutoAdvancingStateMachine
  states: [
    { name: 'initialized',         onAdvance: 'acquireResources',    onRollback: null }
    { name: 'resourcesAcquired',   onAdvance: 'mountContainer',      onRollback: 'releaseResources' }
    { name: 'containerMounted',    onAdvance: 'configureBox',        onRollback: 'unmountVolume' }
    { name: 'boxConfigured',       onAdvance: 'setUpPortForwarding', onRollback: 'removeBoxConfig' }
    { name: 'portForwardingSetUp', onAdvance: 'startContainer',      onRollback: 'releasePortForwarding' }
    { name: 'containerStarted',    onAdvance: 'notifySuccess',       onRollback: 'stopContainer' }
    { name: 'provisioned',         onAdvance: null,                  onRollback: null }
  ]

  constructor: (@id, @name, @containerTemplate, @lxcRoot, @memory, @diskSpace, @publicKeys, @snapshotURL) ->
    @ip = @port = @boxerCallback = null
    super

  create: (@boxerCallback) ->
    console.log "Going to Start"
    this.start()

  acquireResources: (done) ->
    console.log "Acquiring Resources"
    ResourcePool.acquire (err, resources) =>
      if !err
        @ip = "192.168.254.#{resources.ip}"
        @port = parseInt(resources.port)

        console.log "IP --> #{@ip} Port: #{@port}"
      done()

  mountContainer: (done) ->
    console.log "Mounting Container"
    this._execShellCommand "boxer-mount-container",
                           [@lxcRoot, @name, @containerTemplate],
                           sudo: true,
                           done

  configureBox: (done) ->
    console.log "Configuring Box"
    this._execShellCommand "boxer-configure-box",
                           [@lxcRoot, @name, @containerTemplate, @ip]
                           sudo: true,
                           done

  setUpPortForwarding: (done) ->
    console.log "Port Forwarding Set Up"
    this._execShellCommand "boxer-setup-portforwarding",
                           [@ip, @port],
                           sudo: true,
                           done

  startContainer: (done) ->
    console.log "Start Container"
    this._execShellCommand "boxer-start-container",
                           [@name, @ip],
                           sudo: true,
                           done

  notifySuccess: (done) ->
    @boxerCallback?(null)
    delete @boxerCallback
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
    timeout = opts.timeout ? 2000
    sudo = if opts.sudo then 'sudo' else ''

    command = _.flatten([
                          sudo
                          "#{prefix}#{cmd}"
                          _.map(args, (x) -> escapeShellArg(x))
                        ]).join(' ').trim()

    console.log "Executing command #{command}"
    childProcess.exec command, timeout: timeout, (err, stdout, stderr) ->
      done(err)

