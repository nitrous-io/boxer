m = require '../protocol'

module.exports = class MessageParser
  @types:
    'aio.locate' : m.LocateMessage
    'aio.advertise': m.AdvertiseMessage
    'aio.start': m.StartMessage
    'aio.started': m.StartedMessage
    'aio.stop': m.StopMessage
    'aio.stopped': m.StoppedMessage

  @decode: (messageJSON) ->
    parsedMessage = JSON.parse(messageJSON)
    if parsedMessage.type? && (msgKlass = @types[parsedMessage.type])?
      new msgKlass(parsedMessage)
    else
      null
