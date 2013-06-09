process.env.NODE_ENV ?= 'development'
process.title = "boxer"

_                   = require 'underscore'
settings            = require './config/settings'
Boxer               = require './app/lib/boxer'
Ping                = require 'ping'
initAirbrakeClient  = require('./app/lib/utils').initAirbrakeClient
initRedisClientWith = require('./app/lib/utils').initRedisClientWith

if process.env.NODE_ENV == 'production'
  airbrakeClient = initAirbrakeClient(settings.airbrakeAPIKey)
  airbrakeClient?.handleExceptions() # Don't die when exceptions occur

# send uptime/memory usage data to statsd
Repoman = require('repoman')
(new Repoman).collect()

boxer = new Boxer(settings)
boxer.run()

pingRedisMQClient     = initRedisClientWith(settings.redisMQ)
pingRedisStoreClient  = initRedisClientWith(settings.redisStore)

pingServer = new Ping
                      checkFunction: (cb) ->
                        pingRedisMQClient.ping (err, res) ->
                          if err
                            cb err
                          else
                            pingRedisStoreClient.ping (err, res) ->
                              cb err

pingServer.start()

console.log "Started Boxer"

module.exports = boxer
