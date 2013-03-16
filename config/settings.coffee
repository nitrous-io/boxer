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
    awsAccessKeyId: process.env.AWS_ACCESS_KEY_ID
    awsSecretAccessKey: process.env.AWS_SECRET_ACCESS_KEY
    awsRegion: process.env.AWS_REGION
    awsBucket: process.env.AWS_BUCKET
  development: {}
  test:
    id: 'test.action.io'
    redisMQ:
      host: '0.0.0.0'
      port: 65000
      password: null
      database: 1
    redisStore:
      host: '0.0.0.0'
      port: 65000
      password: null
      database: 1
    awsAccessKeyId: 'aws_access_key_id'
    awsSecretAccessKey: 'aws_secret_access_key'
    awsRegion: 'aws_region'
    awsBucket: 'aws_bucket'
  production: {}

exportedSettings = _.extend(runtimes, _.extend(settings.common, settings[env]))

module.exports = exportedSettings
