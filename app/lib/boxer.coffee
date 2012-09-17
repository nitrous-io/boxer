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
    @lxcRoot = settings.lxcRoot
    @hostUrl = settings.hostUrl

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

  _handle:(message) ->
    boxer = this
    logger.info "Received Message: #{message.type} | id: #{message.id}"

    if message.type == protocol.LocateMessage.type
      @publisher.publish @coachChannel,
                         protocol.AdvertiseMessage.construct().encode()

    else if message.type == protocol.CreateMessage.type
      if @id == message.id && (containerTemplate = @runtimes[message.runtime])?
        box = new Box(message.boxId, @redisStoreSettings)
        box.name = message.name
        box.containerTemplate = containerTemplate
        box.lxcRoot = @lxcRoot
        box.memory = message.memory
        box.diskSpace = message.diskSpace
        box.publicKeys = message.publicKeys
        box.snapshotURL = message.snapshotURL
        box.boxerId = @id
        box.hostUrl = @hostUrl

        # These callbacks are called in the context of the Box instance, so @id, @ip, @port, etc. refer to instance variables
        # of the box instance
        successCallback = (err) ->
          createdMessage = new protocol.CreatedMessage({id: boxer.id, boxId: @id, ip: @ip, port: @port, success: true, hostUrl: @hostUrl})
          boxer.publisher.publish boxer.coachChannel, createdMessage.encode()

        errCallback = (err) ->
          createdMessage = new protocol.CreatedMessage({id: boxer.id, boxId: @id, success: false, hostUrl: @hostUrl})
          boxer.publisher.publish boxer.coachChannel, createdMessage.encode()

        box.create successCallback, errCallback
    else if message.type == protocol.StartMessage.type && @id == message.id
      Box.find message.name, @redisStoreSettings, (err, box) ->
        box.start (err) ->
          if !err
            startedMessage = new protocol.StartedMessage({id: boxer.id, boxId: box.id})
            boxer.publisher.publish boxer.coachChannel, startedMessage.encode()
    else if message.type == protocol.StopMessage.type && @id == message.id
      Box.find message.name, @redisStoreSettings, (err, box) ->
        box.stop (err) ->
          if !err
            stoppedMessage = new protocol.StoppedMessage({id: boxer.id, boxId: box.id})
            boxer.publisher.publish boxer.coachChannel, stoppedMessage.encode()
    else if message.type == protocol.DestroyMessage.type && @id == message.id
      Box.find message.name, @redisStoreSettings, (err, box) ->
        box.lxcRoot = boxer.lxcRoot

        box.destroy (err) ->
          if !err
            destroyedMessage = new protocol.DestroyedMessage({id: boxer.id, boxId: box.id})
            boxer.publisher.publish boxer.coachChannel, destroyedMessage.encode()
    else if message.type == protocol.ConfigureMessage.type && @id == message.id
      Box.find message.name, @redisStoreSettings, (err, box) ->
        box.lxcRoot = boxer.lxcRoot

        box.configure message.dataType, message.data, (err) ->
          if !err
            configuredMessage = new protocol.ConfiguredMessage({id: boxer.id, boxId: box.id})
            boxer.publisher.publish boxer.coachChannel, configuredMessage.encode()
