protocol = require '../../protocol'

module.exports = (boxer, message) ->
  return false unless message.type == protocol.LocateMessage.type
  boxer.publisher.publish boxer.coachChannel,
    protocol.AdvertiseMessage.construct().encode()
