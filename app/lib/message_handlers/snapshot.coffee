Box = require '../box'
protocol = require '../../protocol'
async = require 'async'

module.exports = (boxer, message) ->
  return false unless message.type == protocol.SnapshotMessage.type &&
    boxer.id == message.id

  Box.find message.name, (err, box) ->
    box.snapshot message.snapshotName, (err, snapshotUrl) ->
      message = if !err
        new protocol.SnapshottedMessage(
          id: boxer.id,
          boxId: box.id,
          returnVars: message.returnVars
          snapshotUrl: snapshotUrl
        )
      else
        new protocol.InvalidParamsMessage(id: boxer.id)
      boxer.publisher.publish boxer.coachChannel, message.encode()
