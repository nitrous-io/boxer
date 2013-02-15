BaseMessage = require './base_message'

module.exports = class RestoreSnapshotMessage extends BaseMessage
  @type = 'aio:restore_snapshot'

  constructor: (attributes) ->
    @id = attributes.id
    @boxId = attributes.boxId
    @name = attributes.name
    @snapshotId = attributes.snapshotId
    @snapshotName = attributes.snapshotName
    @snapshotUrl = attributes.snapshotUrl
    @data = attributes.data
    super
