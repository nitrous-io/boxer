process.env.NODE_ENV ?= 'development'
process.title = "boxer"

_ = require 'underscore'
settings = require './config/settings'
Boxer = require './app/lib/boxer'
logger = require './app/lib/logger'

initAirbrakeClient = require('./app/lib/utils').initAirbrakeClient

if process.env.NODE_ENV == 'production'
  airbrakeClient = initAirbrakeClient(settings.airbrakeAPIKey)
  airbrakeClient?.handleExceptions() # Don't die when exceptions occur

# send uptime/memory usage data to statsd
Repoman = require('repoman')
(new Repoman).collect()

boxer = new Boxer(settings)
boxer.run()

logger.info "Started Boxer"

module.exports = boxer
