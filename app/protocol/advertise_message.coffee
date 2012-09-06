BaseMessage = require('./base_message')
os = require 'os'

module.exports = class AdvertiseMessage extends BaseMessage
  @type: 'aio.advertise'

  @construct: ->
    settings = require '../../config/settings'
    runtimes = Object.keys(settings.runtimes)

    return new AdvertiseMessage(id: settings.id, type: AdvertiseMessage.type, runtimes: runtimes, freeMemory: os.freemem())

  constructor: (attributes) ->
    @type = attributes.type
    @freeMemory = attributes.freeMemory
    @runtimes = attributes.runtimes
    @id = attributes.id

