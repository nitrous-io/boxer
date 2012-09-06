BaseMessage = require './base_message'

module.exports = class StartMessage extends BaseMessage
  @type = 'aio.start'

  constructor: (attributes) ->
    @id = attributes.id
    @boxId = attributes.boxId
    @runtime = attributes.runtime
    @snapshotURL = attributes.snapshotURL
    @memory = attributes.memory
    @diskSpace = attributes.diskSpace
    @publicKeys = attributes.publicKeys
    @type = attributes.type
