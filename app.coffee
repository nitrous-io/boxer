process.env.NODE_ENV ?= 'development'

_ = require 'underscore'
settings = require './config/settings'
Boxer = require './app/lib/boxer'
logger = require './app/lib/logger'

if settings.airbrakeAPIKey
  airbrake = require('airbrake').createClient settings.airbrakeAPIKey
  airbrake.handleExceptions()

boxer = new Boxer(settings)
boxer.run()

logger.info "Started Boxer"

module.exports = boxer
