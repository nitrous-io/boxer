process.env.NODE_ENV ?= 'development'

_ = require 'underscore'
settings = require './config/settings'
Boxer = require './app/lib/boxer'

# uncaught exception handler
if process.env.NODE_ENV == 'production'
  process.on 'uncaughtException', (err) ->
    console.log err

boxer = new Boxer(settings)
boxer.run()

console.log "Started Boxer"

module.exports = boxer
