BaseMessage = require './base_message'

module.exports = class CreateMessage extends BaseMessage
  @type = 'aio.create'

  constructor: (attributes) ->
    @id = attributes.id
    @boxId = attributes.boxId
    @runtime = attributes.runtime
    @snapshotURL = attributes.snapshotURL
    @memory = attributes.memory
    @diskSpace = attributes.diskSpace
    @publicKeys = attributes.publicKeys
    @name = attributes.name

    super
