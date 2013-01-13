process.env.NODE_ENV ?= 'development'

_ = require 'underscore'
settings = require './config/settings'
Boxer = require './app/lib/boxer'
logger = require './app/lib/logger'
initAirbrakeClient = require('./app/lib/utils').initAirbrakeClient

airbrakeClient = initAirbrakeClient(settings.airbrakeAPIKey)
airbrakeClient?.handleExceptions()

boxer = new Boxer(settings)
boxer.run()

logger.info "Started Boxer"

module.exports = boxer
