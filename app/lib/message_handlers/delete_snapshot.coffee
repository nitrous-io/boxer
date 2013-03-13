Box = require '../box'
protocol = require '../../protocol'
settings = require '../../../config/settings'
s3 = require '../s3'
url = require 'url'

module.exports = (boxer, message) ->
  return false unless message.type == protocol.DeleteSnapshotMessage.type &&
    boxer.id == message.id

  snapshotKey = url.parse(message.snapshotUrl).path.replace('/', '')
  snapshotFile = "/tmp/#{snapshotKey}"
  params = { Bucket: settings.awsBucket, Key: snapshotKey }

  s3.client.deleteObject params, (err) ->
    message = if !err
      new protocol.DeletedSnapshotMessage(
        id: boxer.id,
        returnVars: message.returnVars
      )
    else
      new protocol.InvalidParamsMessage(id: boxer.id)
    boxer.publisher.publish boxer.coachChannel, message.encode()
