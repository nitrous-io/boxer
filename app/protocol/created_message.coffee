BaseMessage = require './base_message'

module.exports = class CreatedMessage extends BaseMessage
  @type = 'aio.created'

  constructor: (attributes) ->
    @id = attributes.id
    @boxId = attributes.boxId
    @ip = attributes.ip
    @port = attributes.port
    @success = attributes.success

    super
