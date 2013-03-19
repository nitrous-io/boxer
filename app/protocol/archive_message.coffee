BaseMessage = require './base_message'

module.exports = class ArchiveMessage extends BaseMessage
  @type = 'aio:archive'

  constructor: (attributes) ->
    @id = attributes.id
    @boxId = attributes.boxId
    @name = attributes.name
    super
