BaseMessage = require './base_message'

module.exports = class RestoreSnapshotMessage extends BaseMessage
  @type = 'aio:restore_snapshot'

  constructor: (attributes) ->
    @id = attributes.id
    @boxId = attributes.boxId
    @name = attributes.name
    @snapshotUrl = attributes.snapshotUrl
    @data = attributes.data
    super
