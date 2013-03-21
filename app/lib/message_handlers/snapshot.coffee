Box = require '../box'
protocol = require '../../protocol'
async = require 'async'

module.exports = (boxer, message) ->
  return false unless message.type == protocol.SnapshotMessage.type &&
    boxer.id == message.id

  async.waterfall [
    (cb) -> Box.find message.name, cb
    (box, cb) -> box.snapshot message.snapshotName, (err, snapshotUrl) -> cb(err, snapshotUrl, box)
  ], (err, snapshotUrl, box) ->
    if !err && snapshotUrl && box
      message = new protocol.SnapshottedMessage(
          id: boxer.id,
          boxId: box.id,
          returnVars: message.returnVars
          snapshotUrl: snapshotUrl
        )
    else
      message = new protocol.InvalidParamsMessage(id: boxer.id)
    boxer.publisher.publish boxer.coachChannel, message.encode()
