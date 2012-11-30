redis = require 'redis'

module.exports = class ResourcePool
  @acquire: (cb) ->
    this.initRedisClient()

    @client.brpoplpush 'available_resources', 'used_resources', 1, (err, resource) ->
      if err || !resource?
        err = new Error "Could Not Acquire Resources"
      cb(err, JSON.parse(resource))

  @release: (resource, cb) ->
    this.initRedisClient()

    if resource?
      multi = @client.multi()
      multi.lrem 'used_resources', 0, resource
      multi.rpush 'available_resources', resource
      multi.exec (err, replies) ->
        cb err
    else
      err = new Error "Invalid Values for IP and Port"
      cb err

  @initRedisClient: () ->
    redisSettings = require('../../config/settings').redisStore

    @client = redis.createClient(redisSettings.port, redisSettings.host)
    @client.auth(redisSettings.password) if redisSettings.password?
    @client.select(redisSettings.database)
