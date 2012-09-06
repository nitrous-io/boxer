redis = require 'redis'

module.exports = (cb) ->
  storeSettings = require('../../config/settings').redisStore
  mqSettings = require('../../config/settings').redisMQ

  cleanerClient = redis.createClient(storeSettings.port, mqSettings.host)
  cleanerClient.auth(storeSettings.password) if storeSettings.password?
  cleanerClient.select(storeSettings.database)

  cleanerClient.flushall ->
    client = redis.createClient(mqSettings.port, mqSettings.host)
    client.auth(mqSettings.password) if mqSettings.password?
    client.select(mqSettings.database)
    cb()

