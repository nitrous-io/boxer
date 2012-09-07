AutoAdvancingStateMachine = require './auto_advancing_state_machine'
ResourcePool = require './resource_pool'
settings = require '../../config/settings'
childProcess = require 'child_process'
escapeShellArg = require('./utils').escapeShellArg
scriptPath = __dirname.replace('app/lib', 'scripts/')
_ = require 'underscore'

module.exports = class Box
  states: [
    { name: 'initialized',         onAdvance: 'acquireResources',    onRollback: null }
    { name: 'resourcesAcquired',   onAdvance: 'mountVolume',         onRollback: 'releaseResources' }
    { name: 'volumeMounted',       onAdvance: 'configureBox',        onRollback: 'unmountVolume' }
    { name: 'boxConfigured',       onAdvance: 'setUpPortForwarding', onRollback: 'removeBoxConfig' }
    { name: 'portForwardingSetUp', onAdvance: 'setUpWebProxy',       onRollback: 'releasePortForwarding' }
    { name: 'webProxySetUp',       onAdvance: 'notifySuccess',       onRollback: 'releaseWebProxy' }
    { name: 'provisoned',          onAdvance: null,                  onRollback: null }
  ]

  constructor: (@name, @containerTemplate, @lxcRoot, @memory, @diskSpace, @publicKeys, @snapshotURL) ->
    @ip = @port = null

  provision: ->
    start()

  acquireResources: (cb) ->
    ResourcePool.acquire (resources, err) =>
      if !err
        @ip = resources.ip
        @port = resources.port
      cb(err)

  mountVolume: (cb) ->
    this._execShellCommand "boxer-mount-volume",
                           [@lxcRoot, @name, @containerTemplate],
                           sudo: true,
                           cb

  configureBox: (cb) ->
    this._execShellCommand "boxer-configure-box",
                           [@lxcRoot, @name, @ip],
                           sudo: true,
                           cb

  setUpPortForwarding: (cb) ->
    this._execShellCommand "boxer-setup-portforwarding",
                           [@ip, @port],
                           sudo: true,
                           cb

  setUpWebProxy: (cb) ->
    this._execShellCommand "boxer-setup-webproxy",
                           [@name, @ip],
                           sudo: true,
                           cb

  notifySuccess: (cb) ->
    this._execShellCommand "boxer-notify-success",
                           [@name],
                           cb

  _execShellCommand: (cmd, args, opts, cb) ->
    if _.isFunction(args)
      cb = args
      args = []
      opts = {}
    else if _.isFunction(opts)
      cb = opts
      opts = {}

    prefix = if opts.prefix then "#{opts.prefix}/".replace(/\/{2,}$/, '/') else scriptPath
    timeout = opts.timeout ? 2000
    sudo = if opts.sudo then 'sudo' else ''

    command = _.flatten([
                          sudo
                          "#{prefix}#{cmd}"
                          _.map(args, (x) -> escapeShellArg(x))
                        ]).join(' ').trim()

    childProcess.exec command, timeout: timeout, (err, stdout, stderr) -> cb(err)

