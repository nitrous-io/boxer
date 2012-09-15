_ = require 'underscore'
env = process.env.NODE_ENV

settings =
  common:
    id: process.env.BOXER_ID
    lxcRoot: '/var/lib/lxc'
    boxerChannel: 'aio-boxer-channel'
    coachChannel: 'aio-coach-channel'
  development:
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
    runtimes: {}
    hostUrl: process.env.HOST_URL
  test:
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
    runtimes:
      test: 'test-container-template'
    hostUrl: 'test.action.io'
  production:
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
    runtimes: {}
    hostUrl: process.env.HOST_URL

module.exports = _.extend settings.common, settings[env]

