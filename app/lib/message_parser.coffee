m = require '../protocol'

module.exports = class MessageParser
  @types:
    'aio:locate'          : m.LocateMessage
    'aio:advertise'       : m.AdvertiseMessage
    'aio:create'          : m.CreateMessage
    'aio:created'         : m.CreatedMessage
    'aio:start'           : m.StartMessage
    'aio:started'         : m.StartedMessage
    'aio:stop'            : m.StopMessage
    'aio:stopped'         : m.StoppedMessage
    'aio:destroy'         : m.DestroyMessage
    'aio:destroyed'       : m.DestroyedMessage
    'aio:configure'       : m.ConfigureMessage
    'aio:configured'      : m.ConfiguredMessage
    'aio:invalid:params'  : m.InvalidParamsMessage

  @decode: (messageJSON) ->
    parsedMessage = JSON.parse(messageJSON)
    if parsedMessage.type? && (msgKlass = @types[parsedMessage.type])?
      new msgKlass(parsedMessage)
    else
      null
