BaseMessage = require './base_message'

module.exports = class SnapshotMessage extends BaseMessage
  @type = 'aio:snapshot'

  # data may contains list of files that should be excluded
  constructor: (attributes) ->
    @id = attributes.id
    @boxId = attributes.boxId
    @name = attributes.name
    @data = attributes.data
    super
