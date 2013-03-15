Box = require '../box'
protocol = require '../../protocol'
async = require 'async'

module.exports = (boxer, message) ->
  return false unless (message.type == protocol.ArchiveMessage.type &&
    boxer.id == message.id)

  async.waterfall [
    (cb) -> Box.find message.name, cb
    (box, cb) -> box.archive (err, snapshotUrl) -> cb(err, snapshotUrl, box)
  ], (err, snapshotUrl, box) ->
    message = if !err
      new protocol.ArchivedMessage
        boxId: box.id
        id: boxer.id
        name: message.name
        snapshotUrl: snapshotUrl
    else
      new protocol.InvalidParamsMessage(id: boxer.id)
    boxer.publisher.publish boxer.coachChannel, message.encode()
