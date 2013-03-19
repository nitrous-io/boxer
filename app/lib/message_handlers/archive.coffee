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
    if !box
      message = new protocol.InvalidParamsMessage(id: boxer.id)
    else
      if !err && snapshotUrl
        message = new protocol.ArchivedMessage
          boxId: box.id
          id: boxer.id
          name: message.name
          snapshotUrl: snapshotUrl
          success: true
      else
        message = new protocol.ArchivedMessage
          boxId: box.id
          id: boxer.id
          name: message.name
          success: false
    boxer.publisher.publish boxer.coachChannel, message.encode()
