BaseMessage = require './base_message'

module.exports = class ConfigureMessage extends BaseMessage
  @type = 'aio.configure'

  @dataTypes =
    'aio.configure.public_keys': 'aio.configured.public_keys'

  constructor: (attributes) ->
    @id = attributes.id
    @name = attributes.name
    @data = attributes.data
    if (ConfigureMessage.datatypes[attributes.dataType])?
      @dataType = attributes.dataType
    super

