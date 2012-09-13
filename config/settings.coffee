_ = require 'underscore'
env = process.env.NODE_ENV

settings =
  common:
    id: '400ed6e6-d633-42dc-b42e-8b0604bb29e1'
    lxcRoot: '/var/lib/lxc'
    boxerChannel: 'aio-boxer-channel'
    coachChannel: 'aio-coach-channel'
  development:
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
    runtimes: {}
    containerIdleTime: 5 * 60
    hostUrl: 'dev.action.io'
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
    containerIdleTime: 5 * 60
    hostUrl: 'test.action.io'
  production:
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
    runtimes: {}
    containerIdleTime: 5 * 60
    hostUrl: 'test.action.io'

module.exports = _.extend settings.common, settings[env]

