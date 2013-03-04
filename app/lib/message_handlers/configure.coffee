Box = require '../box'
protocol = require '../../protocol'

module.exports = (boxer, message) ->
  return false unless (message.type == protocol.ConfigureMessage.type &&
    boxer.id == message.id)

  Box.find message.name, (err, box) ->
    box.configure message.dataType, message.data, (err) ->
      message = if !err
        new protocol.ConfiguredMessage
          boxId: box.id
          id: boxer.id
          dataType: message.dataType
          returnVars: message.returnVars
      else
        new protocol.InvalidParamsMessage(id: boxer.id)
      boxer.publisher.publish boxer.coachChannel, message.encode()
