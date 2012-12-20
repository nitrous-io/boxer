redis = require 'redis'

module.exports = class ResourcePool
  @acquire: (cb) ->
    this.initRedisClient()
    self = this

    @client.brpoplpush 'aio:available_resources', 'aio:used_resources', 1, (err, ip) ->
      if err || !ip?
        err = new Error "Could Not Acquire Resources"
        cb(err, null)
      else
        self.client.hgetall "aio:nwr:#{ip}", (err, resource) ->
          resource.ip = ip
          cb(err, resource)

  @release: (resource, cb) ->
    this.initRedisClient()

    if resource?
      multi = @client.multi()
      multi.lrem 'aio:used_resources', 0, resource.ip
      multi.rpush 'aio:available_resources', resource.ip
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
