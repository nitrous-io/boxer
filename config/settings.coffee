_ = require 'underscore'
env = process.env.NODE_ENV

settings =
  common:
    id: '400ed6e6-d633-42dc-b42e-8b0604bb29e1'
    lxcRoot: '/var/lib/lxc'
  development:
    nats:
      host: '0.0.0.0'
      port: 4222
    redis:
      host: '0.0.0.0'
      port: 6379
      password: null
      database: 0
    runtimes: {}
    containerIdleTime: 5 * 60
  test:
    nats:
      host: '0.0.0.0'
      port: 4222
    redis:
      host: '0.0.0.0'
      port: 6379
      password: null
      database: 1
    runtimes:
      test: 'test-container-template'
    containerIdleTime: 5 * 60
  production:
    nats:
      host: '0.0.0.0'
      port: 4222
    redis:
      host: '0.0.0.0'
      port: 6379
      password: null
      database: 2
    runtimes: {}
    containerIdleTime: 5 * 60

module.exports = _.extend settings.common, settings[env]

