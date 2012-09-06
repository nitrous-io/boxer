m = require '../protocol'

module.exports = class MessageParser
  @_types:
    'aio.locate' : m.LocateMessage
    'aio.advertise': m.AdvertiseMessage

  @decode: (messageJSON) ->
    parsedMessage = JSON.parse(messageJSON)

    if parsedMessage.type? && (msgKlass = @_types[parsedMessage.type])?
      new msgKlass(parsedMessage)
    else
      throw new Error("Invalid Message Type")
