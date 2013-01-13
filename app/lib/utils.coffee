module.exports =
  escapeShellArg: (string) ->
    if typeof string == 'number'
      return "'#{string.toString()}'"
    if typeof string == 'string'
      return "'" + string.replace(/'/g, "'\"'\"'") + "'"
    null

  initRedisClientWith: (settings) ->
    database = null

    if settings
      database = require('redis').createClient(settings.port, settings.host)
      database.auth(settings.password) if settings.password?
      database.select(settings.database)

    database

  initAirbrakeClient: (airbrakeAPIKey) ->
    airbrakeClient = null

    if airbrakeAPIKey
      airbrakeClient = require('airbrake').createClient airbrakeAPIKey

    airbrakeClient

