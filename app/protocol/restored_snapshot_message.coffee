BaseMessage = require './base_message'

module.exports = class RestoredSnapshotMessage extends BaseMessage
  @type = 'aio:restored_snapshot'

  constructor: (attributes) ->
    @id = attributes.id
    @boxId = attributes.boxId
    @name = attributes.name
    @snapshotId = attributes.snapshotId
    @snapshotName = attributes.snapshotName
    @snapshotUrl = attributes.snapshotUrl
    @data = attributes.data
    super
