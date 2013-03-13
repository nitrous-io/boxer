_ = require 'underscore'
logger = require './logger'
childProcess = require 'child_process'

escapeShellArg = (string) ->
  if typeof string == 'number'
    return "'#{string.toString()}'"
  if typeof string == 'string'
    return "'" + string.replace(/'/g, "'\"'\"'") + "'"
  null

module.exports =
  initRedisClientWith: (settings) ->
    client = null
    if settings
      client = require('redis').createClient(settings.port, settings.host)
      client.auth(settings.password) if settings.password?
      client.select(settings.database)
      # Catch errors which will cause the Redis client to reconnect
      # without killing the process
      client.on 'error', (err) -> console.log 'Redis Error: ', err
    client

  initAirbrakeClient: (airbrakeAPIKey) ->
    airbrakeClient = null
    if airbrakeAPIKey
      airbrakeClient = require('airbrake').createClient airbrakeAPIKey
    airbrakeClient

  execShellCommand: (cmd, args, opts, done) ->
    if _.isFunction(args)
      done = args
      args = []
      opts = {}
    else if _.isFunction(opts)
      done = opts
      opts = {}

    scriptPath = __dirname.replace('app/lib', 'scripts/')
    prefix = if process.env.NODE_ENV == 'production'
      '/var/apps/boxer/current/scripts/'
    else
      scriptPath
    sudo = if opts.sudo then 'sudo' else ''

    command = _.flatten([
      sudo
      prefix + cmd
      _.map(args, escapeShellArg)
    ]).join(' ').trim()

    logger.info "Executing command #{command}"
    start = new Date()
    childProcess.exec command, timeout: 0, (err, stdout, stderr) ->
      if err
        logger.info "boxer_exec_shell_command_err: #{stderr}"
        throw err
      logger.info "command: #{command} took: #{+(new Date() - start)} ms"
      done(err)
