MessageParser = require './message_parser'
Box = require './box'
protocol = require '../protocol'
initRedisClientWith = require('./utils').initRedisClientWith
logger = require './logger'

module.exports = class Boxer
  @ADVERTISE_INTERVAL = 5 # seconds
  @CONTAINER_IDLE_TIME = 5 * 60 # seconds

  constructor: (settings)->
    @id = settings.id
    @runtimes = settings.runtimes

    @boxerChannel = settings.boxerChannel
    @coachChannel = settings.coachChannel

    @redisStoreSettings = settings.redisStore
    @redisMQSettings = settings.redisMQ

    @subscriber = initRedisClientWith(@redisMQSettings)
    # We need a separate client to publish events, since
    # once a redis client is in 'subscribe' mode,
    # it can't perform other operations
    @publisher = initRedisClientWith(@redisMQSettings)

  cleanup: ->
    clearInterval(@advertiseTimer) if @advertiseTimer?

    @subscriber.unsubscribe()
    @subscriber = @publisher = null

  run: (done) ->
    boxer = this
    @subscriber.subscribe @boxerChannel, (err, result) ->
      if !err
        boxer.subscriber.on 'message', (channel, rawMessage) ->
          boxer._handle(MessageParser.decode(rawMessage))

        boxer.advertiseTimer = setInterval boxer.sendAdvertiseMessage,
                                           Boxer.ADVERTISE_INTERVAL * 1000
        done?()
      else
        throw err


  sendAdvertiseMessage: =>
    advertiseMessage = protocol.AdvertiseMessage.construct()
    @publisher.publish @coachChannel,
                       protocol.AdvertiseMessage.construct().encode()

  _handle: (message) ->
    boxer = this
    returnVars = message.returnVars

    logger.info "Received Message: #{message.type} | id: #{message.id}"

    if message.type == protocol.LocateMessage.type
      @publisher.publish @coachChannel,
                         protocol.AdvertiseMessage.construct().encode()

    else if message.type == protocol.CreateMessage.type
      if @id == message.id && (containerTemplate = @runtimes[message.runtime])?
        box = new Box(message.boxId, @redisStoreSettings)
        box.name = message.name
        box.containerTemplate = containerTemplate
        box.memory = message.memory
        box.diskSpace = message.diskSpace
        box.publicKeys = message.publicKeys
        box.snapshotURL = message.snapshotURL
        box.boxerId = @id

        # These callbacks are called in the context of the Box instance, so @id, @ip, @port, etc. refer to instance variables
        # of the box instance
        successCallback = (err) ->
          createdMessage = new protocol.CreatedMessage({id: boxer.id, boxId: @id, port: @port, success: true})
          boxer.publisher.publish boxer.coachChannel, createdMessage.encode()

        errCallback = (err) ->
          createdMessage = new protocol.CreatedMessage({id: boxer.id, boxId: @id, success: false})
          boxer.publisher.publish boxer.coachChannel, createdMessage.encode()

        box.create successCallback, errCallback
    else if message.type == protocol.StartMessage.type && @id == message.id
      Box.find message.name, (err, box) ->
        box.start (err) ->
          if !err
            startedMessage = new protocol.StartedMessage({id: boxer.id, boxId: box.id, returnVars: returnVars})
            boxer.publisher.publish boxer.coachChannel, startedMessage.encode()
          else
            boxer.publisher.publish boxer.coachChannel,
                             new protocol.InvalidParamsMessage(id: boxer.id).encode()
    else if message.type == protocol.StopMessage.type && @id == message.id
      Box.find message.name, (err, box) ->
        box.stop (err) ->
          if !err
            stoppedMessage = new protocol.StoppedMessage({id: boxer.id, boxId: box.id, returnVars: returnVars})
            boxer.publisher.publish boxer.coachChannel, stoppedMessage.encode()
          else
            boxer.publisher.publish boxer.coachChannel,
                             new protocol.InvalidParamsMessage(id: boxer.id).encode()
    else if message.type == protocol.RestartMessage.type && @id == message.id
      Box.find message.name, (err, box) ->
        box.restart (err) ->
          if !err
            restartedMessage = new protocol.RestartedMessage({id: boxer.id, boxId: box.id, returnVars: returnVars})
            boxer.publisher.publish boxer.coachChannel, restartedMessage.encode()
          else
            boxer.publisher.publish boxer.coachChannel,
                             new protocol.InvalidParamsMessage(id: boxer.id).encode()
    else if message.type == protocol.DestroyMessage.type && @id == message.id
      Box.find message.name, (err, box) ->
        box.destroy (err) ->
          if !err
            destroyedMessage = new protocol.DestroyedMessage({id: boxer.id, boxId: box.id, returnVars: returnVars})
            boxer.publisher.publish boxer.coachChannel, destroyedMessage.encode()
          else
            boxer.publisher.publish boxer.coachChannel,
                             new protocol.InvalidParamsMessage(id: boxer.id).encode()
    else if message.type == protocol.ConfigureMessage.type && @id == message.id
      Box.find message.name, (err, box) ->
        box.configure message.dataType, message.data, (err) ->
          if !err
            configuredMessage = new protocol.ConfiguredMessage({id: boxer.id, boxId: box.id, dataType: message.dataType, returnVars: returnVars})
            boxer.publisher.publish boxer.coachChannel, configuredMessage.encode()
          else
            boxer.publisher.publish boxer.coachChannel,
                             new protocol.InvalidParamsMessage(id: boxer.id).encode()
    else if message.type == protocol.SnapshotMessage.type && @id == message.id
      Box.find message.name, (err, box) ->
        box.snapshot message.snapshotName, (err, snapshotUrl) ->
          message = if !err
            new protocol.SnapshottedMessage(
              id: boxer.id,
              boxId: box.id,
              returnVars: returnVars
              snapshotId: message.snapshotId
              snapshotName: message.snapshotName
              snapshotUrl: snapshotUrl
            )
          else
            new protocol.InvalidParamsMessage(id: boxer.id)
          boxer.publisher.publish boxer.coachChannel, message.encode()
    else if message.type == protocol.RestoreSnapshotMessage.type && @id == message.id
      Box.find message.name, (err, box) ->
        box.restore_snapshot message.snapshotUrl, (err) ->
          message = if !err
            new protocol.RestoredSnapshotMessage(
              id: boxer.id,
              boxId: box.id,
              returnVars: returnVars
              snapshotUrl: message.snapshotUrl
            )
          else
            new protocol.InvalidParamsMessage(id: boxer.id)
          boxer.publisher.publish boxer.coachChannel, message.encode()
