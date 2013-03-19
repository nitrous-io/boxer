Box = require '../box'
settings = require '../../../config/settings'
protocol = require '../../protocol'
async = require 'async'

module.exports = (boxer, message) ->
  return false unless message.type == protocol.CreateMessage.type &&
    boxer.id == message.id &&
    (boxer.runtimes[message.runtime] || message.snapshotURL)

  box = new Box(message.boxId, settings.redisStore)
  box.name = message.name
  box.containerTemplate = boxer.runtimes[message.runtime]
  box.memory = message.memory
  box.diskSpace = message.diskSpace
  box.publicKeys = message.publicKeys
  box.snapshotURL = message.snapshotURL
  box.boxerId = message.id

  # These callbacks are called in the context of the Box instance, so @id, @ip,
  # @port, etc. refer to instance variables of the box instance
  successCallback = (err) ->
    createdMessage = new protocol.CreatedMessage
      id: boxer.id
      boxId: @id
      port: @port
      success: true
    boxer.publisher.publish boxer.coachChannel, createdMessage.encode()

  errCallback = (err) ->
    createdMessage = new protocol.CreatedMessage
      id: boxer.id
      boxId: @id
      success: false
    boxer.publisher.publish boxer.coachChannel, createdMessage.encode()

  box.create successCallback, errCallback
