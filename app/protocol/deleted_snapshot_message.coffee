BaseMessage = require './base_message'

module.exports = class DeletedSnapshotMessage extends BaseMessage
  @type = 'aio:deleted_snapshot'

  constructor: (attributes) ->
    @id = attributes.id
    @boxId = attributes.boxId
    @name = attributes.name
    super
