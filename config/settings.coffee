_ = require 'underscore'
runtimes = require './runtimes'
env = process.env.NODE_ENV

settings =
  common:
    lxcRoot: '/var/lib/lxc'
    boxerChannel: 'aio-boxer-channel'
    coachChannel: 'aio-coach-channel'
  development:
    id: process.env.BOXER_ID
    redisMQ:
      host: process.env.REDIS_MQ_HOST
      port: process.env.REDIS_MQ_PORT
      password: null
      database: 0
    redisStore:
      host: process.env.REDIS_STORE_HOST
      port: process.env.REDIS_STORE_PORT
      password: null
      database: 0
  test:
    id: 'test.action.io'
    redisMQ:
      host: '0.0.0.0'
      port: 6379
      password: null
      database: 0
    redisStore:
      host: '0.0.0.0'
      port: 6379
      password: null
      database: 0
  production:
    id: process.env.BOXER_ID
    redisMQ:
      host: process.env.REDIS_MQ_HOST
      port: process.env.REDIS_MQ_PORT
      password: null
      database: 0
    redisStore:
      host: process.env.REDIS_STORE_HOST
      port: process.env.REDIS_STORE_PORT
      password: null
      database: 0

exportedSettings = _.extend(runtimes, _.extend(settings.common, settings[env]))

module.exports = exportedSettings

