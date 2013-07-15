BaseMessage = require './base_message'

module.exports = class ArchivedMessage extends BaseMessage
  @type = 'aio:archived'

  constructor: (attributes) ->
    @id = attributes.id
    @boxId = attributes.boxId
    @name = attributes.name
    @snapshotURL = attributes.snapshotURL
    super
