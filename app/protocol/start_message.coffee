BaseMessage = require './base_message'

module.exports = class StartMessage extends BaseMessage
  @type = 'aio:start'

  constructor: (attributes) ->
    @id = attributes.id
    @boxId = attributes.boxId
    @name = attributes.name
    @data = attributes.data
    super
