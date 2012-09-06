redis = require 'redis'

module.exports = (cb) ->
  settings = require('../../config/settings').redis

  cleanerClient = redis.createClient(settings.port, settings.host)
  cleanerClient.auth(settings.password) if settings.password?
  cleanerClient.select(settings.database)

  cleanerClient.flushall ->
    cb()

