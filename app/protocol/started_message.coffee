BaseMessage = require './base_message'

module.exports = class StartedMessage extends BaseMessage
  @type = 'aio.started'

  constructor: (attributes) ->
    @id = attributes.id
    @boxId = attributes.boxId
    @ip = attributes.ip
    @port = attributes.port
    @type = StartedMessage.type
