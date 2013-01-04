process.env.NODE_ENV ?= 'development'

Box = require './app/lib/box'
logger = require './app/lib/logger'

Box.startAll ->
  logger.info "Restarted All Boxes"
  process.exit(code=0)
