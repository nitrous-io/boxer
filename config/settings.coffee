_ = require 'underscore'
runtimes = require './runtimes'
env = process.env.NODE_ENV

settings =
  common:
    boxerChannel: 'aio-boxer-channel'
    coachChannel: 'aio-coach-channel'
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
    airbrakeAPIKey: process.env.AIRBRAKE_API_KEY
    mountMethod: process.env.MOUNT_METHOD
    selectedVG: process.env.SELECTED_VG
  development: {}
  test:
    id: 'test.action.io'
    redisMQ:
      host: process.env.REDIS_MQ_HOST
      port: process.env.REDIS_MQ_PORT
      password: null
      database: 2
    redisStore:
      host: process.env.REDIS_STORE_HOST
      port: process.env.REDIS_STORE_PORT
      password: null
      database: 2
  production: {}

exportedSettings = _.extend(runtimes, _.extend(settings.common, settings[env]))

module.exports = exportedSettings
