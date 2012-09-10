m = require '../protocol'

module.exports = class MessageParser
  @_types:
    'aio.locate' : m.LocateMessage
    'aio.advertise': m.AdvertiseMessage
    'aio.start': m.StartMessage
    'aio.started': m.StartedMessage

  @decode: (messageJSON) ->
    parsedMessage = JSON.parse(messageJSON)
    if parsedMessage.type? && (msgKlass = @_types[parsedMessage.type])?
      new msgKlass(parsedMessage)
    else
      null
