Box = require '../box'
protocol = require '../../protocol'

module.exports = (boxer, message) ->
  return false unless message.type == protocol.DestroyMessage.type &&
    boxer.id == message.id

  Box.find message.name, (err, box) ->
    box.destroy (err) ->
      message = if !err
        new protocol.DestroyedMessage
          id: boxer.id
          boxId: box.id
          returnVars: message.returnVars
      else
        new protocol.InvalidParamsMessage(id: boxer.id)
      boxer.publisher.publish boxer.coachChannel, message.encode()
