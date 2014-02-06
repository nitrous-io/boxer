BaseMessage = require './base_message'

module.exports = class SnapshotMessage extends BaseMessage
  @type = 'aio:snapshot'

  constructor: (attributes) ->
    @id = attributes.id
    @name = attributes.name
    @snapshotId = attributes.snapshotId
    super
