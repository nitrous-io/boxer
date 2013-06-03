process.env.NODE_ENV ?= 'development'

Box = require './app/lib/box'

Box.startAll ->
  console.log "Restarted All Boxes"
  process.exit(code=0)
