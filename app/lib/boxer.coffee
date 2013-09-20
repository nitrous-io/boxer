MessageParser = require './message_parser'
Box = require './box'
protocol = require '../protocol'
initRedisClientWith = require('./utils').initRedisClientWith

module.exports = class Boxer
  @ADVERTISE_INTERVAL = 5 # seconds
  @CONTAINER_IDLE_TIME = 5 * 60 # seconds

  constructor: (settings)->
    @id = settings.id
    @runtimes = settings.runtimes
    @selectedDisk = settings.selectedDisk

    @boxerChannel = settings.boxerChannel
    @coachChannel = settings.coachChannel

    @redisStoreSettings = settings.redisStore
    @redisMQSettings = settings.redisMQ

    @subscriber = initRedisClientWith(@redisMQSettings, "boxerSubscriber")
    # We need a separate client to publish events, since
    # once a redis client is in 'subscribe' mode,
    # it can't perform other operations
    @publisher = initRedisClientWith(@redisMQSettings, "boxerPublisher")

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

  _handle:(message) ->
    boxer = this
    returnVars = message.returnVars

    console.log "Received Message: #{message.type} | id: #{message.id}"

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
        box.cpuShares = message.cpuShares if message.cpuShares

        box.boxerId = @id
        box.disk = @selectedDisk
        box.aufs = true

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
          dataType = protocol.ConfigureMessage.dataTypes[message.dataType]
          configuredMessage = new protocol.ConfiguredMessage({id: boxer.id, boxId: box.id, dataType: dataType, data: message.data, success: true, returnVars: returnVars})
          if message.dataType == "aio:configure:change_specs"
            data = configuredMessage.data
            data.memory = parseInt box.memory, 10
            data.diskSpace = parseInt box.diskSpace, 10

          if err
            configuredMessage.success = false

          boxer.publisher.publish boxer.coachChannel, configuredMessage.encode()
    else if message.type == protocol.InfoRequestMessage.type && @id == message.id
      Box.find message.name, (err, box) ->
        box.info (err, info) ->
          infoResponseMessage = new protocol.InfoResponseMessage({id: boxer.id, boxId: box.id, success: true, returnVars: returnVars})

          if !err
            infoResponseMessage.info = info
          else
            infoResponseMessage.success = false

          boxer.publisher.publish boxer.coachChannel, infoResponseMessage.encode()
