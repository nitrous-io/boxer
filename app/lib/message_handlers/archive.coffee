Box = require '../box'
protocol = require '../../protocol'

module.exports = (boxer, message) ->
  return false unless (message.type == protocol.ArchiveMessage.type &&
    boxer.id == message.id)

  Box.find message.name, (err, box) ->
    box.archive (err, snapshotUrl) ->
      message = if !err
        new protocol.ArchivedMessage
          boxId: box.id
          id: boxer.id
          name: message.name
          snapshotUrl: snapshotUrl
      else
        new protocol.InvalidParamsMessage(id: boxer.id)
      boxer.publisher.publish boxer.coachChannel, message.encode()
