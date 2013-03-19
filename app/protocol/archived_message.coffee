BaseMessage = require './base_message'

module.exports = class ArchivedMessage extends BaseMessage
  @type = 'aio:archived'

  constructor: (attributes) ->
    @id = attributes.id
    @boxId = attributes.boxId
    @snapshotUrl = attributes.snapshotUrl
    @name = attributes.name
    @success = attributes.success
    super
