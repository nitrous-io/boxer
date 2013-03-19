Box = require '../box'
protocol = require '../../protocol'

module.exports = (boxer, message) ->
  return false unless message.type == protocol.StartMessage.type &&
    boxer.id == message.id

  Box.find message.name, (err, box) ->
    box.start (err) ->
      message = if !err
        new protocol.StartedMessage
          id: boxer.id
          boxId: box.id
          returnVars: message.returnVars
      else
        new protocol.InvalidParamsMessage(id: boxer.id)
      boxer.publisher.publish boxer.coachChannel, message.encode()
