process.env.NODE_ENV ?= 'development'

Box = require './app/lib/box'

Box.configureAll ->
  console.log "Configured All Boxes"
  process.exit(code=0)

