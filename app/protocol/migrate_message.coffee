BaseMessage = require './base_message'

module.exports = class MigrateMessage extends BaseMessage
  @type = 'aio:migrate'

  @dataTypes =
    'aio:migrate:snapshot': 'aio:migrate:snapshotted'
    'aio:migrate:create': 'aio:migrate:created'

  # similar to CreateMessage, but we will add more fields
  # a new box host to migrate the box to.
  constructor: (attributes) ->
    @id = attributes.id
    @boxId = attributes.boxId
    @runtime = attributes.runtime
    @name = attributes.name
    @snapshotURL = attributes.snapshotURL
    @memory = attributes.memory
    @diskSpace = attributes.diskSpace
    @publicKeys = attributes.publicKeys
    @sshKeyPair = attributes.sshKeyPair

    @excludedHosts = attributes.excludedHosts

    if (MigrateMessage.dataTypes[attributes.dataType])?
      @dataType = attributes.dataType
    super
