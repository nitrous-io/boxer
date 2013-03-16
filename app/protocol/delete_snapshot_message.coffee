BaseMessage = require './base_message'

module.exports = class DeleteSnapshotMessage extends BaseMessage
  @type = 'aio:delete_snapshot'

  constructor: (attributes) ->
    @id = attributes.id
    @boxId = attributes.boxId
    @name = attributes.name
    @snapshotUrl = attributes.snapshotUrl
    super
