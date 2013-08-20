BaseMessage = require './base_message'

module.exports = class MigratedMessage extends BaseMessage
  @type = 'aio:migrated'

  constructor: (attributes) ->
    @id = attributes.id
    @boxId = attributes.boxId
    @port = attributes.port
    @success = attributes.success
    super
