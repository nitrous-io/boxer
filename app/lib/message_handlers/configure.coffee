Box = require '../box'
protocol = require '../../protocol'
async = require 'async'

module.exports = (boxer, message) ->
  return false unless (message.type == protocol.ConfigureMessage.type &&
    boxer.id == message.id)

  async.waterfall [
    (cb) -> Box.find message.name, cb
    (box, cb) -> box.configure message.dataType, message.data, (err) -> cb(err, box)
  ], (err, box) ->
    if !err && box
      message = new protocol.ConfiguredMessage
        boxId: box.id
        id: boxer.id
        dataType: message.dataType
        returnVars: message.returnVars
    else
      message = new protocol.InvalidParamsMessage(id: boxer.id)
    boxer.publisher.publish boxer.coachChannel, message.encode()
