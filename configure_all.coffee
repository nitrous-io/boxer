process.env.NODE_ENV ?= 'development'

Box = require './app/lib/box'
logger = require './app/lib/logger'

Box.configureAll ->
  logger.info "Configured All Boxes"
  process.exit(code=0)

