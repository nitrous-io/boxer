redis = require 'redis'

module.exports = class ResourcePool
  @acquire: (cb) ->
    err = null
    resources = {}
    this.initRedisClient()

    multi = @client.multi()
    multi.brpoplpush 'available_ips', 'used_ips', 1
    multi.brpoplpush 'available_ports', 'used_ports', 1
    multi.exec (err, replies) ->
      if !err && replies[0]? && replies[1]?
        resources.ip = replies[0]
        resources.port = replies[1]
      else
        err = new Error "Could Not Acquire Resources"

      cb(err, resources)

  @release: (resources, cb) ->
    ip = resources.ip
    port = resources.port

    if ip && port
      multi = @client.multi()
      multi.lrem 'used_ports', 0, port
      multi.rpush 'available_ports', port
      multi.lrem 'used_ips', 0, ip
      multi.rpush 'available_ips', ip
      multi.exec (err, replies) ->
        cb(err)
    else
      err = new Error "Invalid Values for IP and Port"
      cb(err)

  @initRedisClient: () ->
    redisSettings = require('../../config/settings').redisStore

    @client = redis.createClient(redisSettings.port, redisSettings.host)
    @client.auth(redisSettings.password) if redisSettings.password?
    @client.select(redisSettings.database)
