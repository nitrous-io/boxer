BaseMessage = require './base_message'

module.exports = class ConfigureMessage extends BaseMessage
  @type = 'aio:configure'

  @dataTypes =
    'aio:configure:add_public_key': 'aio:configured:add_public_key'
    'aio:configure:remove_public_key': 'aio:configured:remove_public_key'

  constructor: (attributes) ->
    @id = attributes.id
    @name = attributes.name
    @data = attributes.data
    if (ConfigureMessage.dataTypes[attributes.dataType])?
      @dataType = attributes.dataType
    super

