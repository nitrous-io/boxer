Box = require '../box'
protocol = require '../../protocol'
async = require 'async'

module.exports = (boxer, message) ->
  return false unless message.type == protocol.RestartMessage.type &&
    boxer.id == message.id

  async.waterfall [
    (cb) -> Box.find message.name, cb
    (box, cb) -> box.restart (err) -> cb(err, box)
  ], (err, box) ->
    if !err && box
      message = new protocol.RestartedMessage
        id: boxer.id
        boxId: box.id
        returnVars: message.returnVars
    else
      message = new protocol.InvalidParamsMessage(id: boxer.id)
    boxer.publisher.publish boxer.coachChannel, message.encode()
