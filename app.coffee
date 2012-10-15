process.env.NODE_ENV ?= 'development'

_ = require 'underscore'
settings = require './config/settings'
Boxer = require './app/lib/boxer'
logger = require './app/lib/logger'

# uncaught exception handler
if process.env.NODE_ENV == 'production' || process.env.NODE_ENV == 'staging'
  airbrake = require('airbrake').createClient(settings.airbrakeKey)
  airbrake.handleExceptions()

boxer = new Boxer(settings)
boxer.run()

logger.info "Started Boxer"

module.exports = boxer
