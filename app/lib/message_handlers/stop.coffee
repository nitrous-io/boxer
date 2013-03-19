Box = require '../box'
protocol = require '../../protocol'
async = require 'async'

module.exports = (boxer, message) ->
  return false unless message.type == protocol.StopMessage.type &&
    boxer.id == message.id

  Box.find message.name, (err, box) ->
    box.stop (err) ->
      message = if !err
        new protocol.StoppedMessage
          id: boxer.id
          boxId: box.id
          returnVars: message.returnVars
      else
        new protocol.InvalidParamsMessage(id: boxer.id)
      boxer.publisher.publish boxer.coachChannel, message.encode()
