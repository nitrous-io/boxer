AWS = require 'aws-sdk'
settings = require '../../config/settings'

AWS.config.update
  accessKeyId: settings.awsAccessKeyId
  secretAccessKey: settings.awsSecretAccessKey
  region: settings.awsRegion

module.exports = new AWS.S3()
