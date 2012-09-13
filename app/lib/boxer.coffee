MessageParser = require './message_parser'
Box = require './box'
protocol = require '../protocol'
initRedisClientWith = require('./utils').initRedisClientWith

module.exports = class Boxer
  constructor: (settings)->
    @id = settings.id
    @runtimes = settings.runtimes
    @lxcRoot = settings.lxcRoot
    @containerIdleTime = settings.containerIdleTime

    @boxerChannel = settings.boxerChannel
    @coachChannel = settings.coachChannel

    @redisStoreSettings = settings.redisStore

    @subscriber = initRedisClientWith(settings.redisMQ)
    # We need a separate client to publish events, since
    # once a redis client is in 'subscribe' mode,
    # it can't perform other operations
    @publisher = initRedisClientWith(@redisStoreSettings)

  cleanup: ->
    @subscriber.unsubscribe()
    @subscriber = @publisher = null

  run: (done) ->
    boxer = this
    @subscriber.subscribe @boxerChannel, (err, result) ->
      if !err
        boxer.subscriber.on 'message', (channel, rawMessage) ->
          boxer._handle(MessageParser.decode(rawMessage))
        done?()
      else
        throw err

  _handle:(message) ->
    boxer = this

    if message.type == protocol.LocateMessage.type
      @publisher.publish @coachChannel,
                         protocol.AdvertiseMessage.construct().encode()

    else if message.type == protocol.CreateMessage.type
      if @id == message.id && (containerTemplate = @runtimes[message.runtime])?
        box = new Box(message.boxId, @redisStoreSettings)
        box.hostName = message.hostName
        box.containerTemplate = containerTemplate
        box.lxcRoot = @lxcRoot
        box.memory = message.memory
        box.diskSpace = message.diskSpace
        box.publicKeys = message.publicKeys
        box.snapshotURL = message.snapshotURL

        successCallback = (err) ->
          startedMessage = new protocol.CreatedMessage({id: boxer.id, boxId: @id, ip: @ip, port: @port, success: true})
          boxer.publisher.publish boxer.coachChannel, startedMessage.encode()

        errCallback = (err) ->
          startedMessage = new protocol.CreatedMessage({id: boxer.id, boxId: @id, success: false})
          boxer.publisher.publish boxer.coachChannel, startedMessage.encode()

        box.create successCallback, errCallback
    else if message.type == protocol.StartMessage.type && @id == message.id
      Box.find message.boxId, @redisStoreSettings, (err, box) ->
        box.start (err) ->
          if !err
            startedMessage = new protocol.StartedMessage({id: boxer.id, boxId: box.id})
            boxer.publisher.publish boxer.coachChannel, startedMessage.encode()
    else if message.type == protocol.StopMessage.type && @id == message.id
      Box.find message.boxId, @redisStoreSettings, (err, box) ->
        box.stop (err) ->
          if !err
            stoppedMessage = new protocol.StoppedMessage({id: boxer.id, boxId: box.id})
            boxer.publisher.publish boxer.coachChannel, stoppedMessage.encode()
    else if message.type == protocol.DestroyMessage.type && @id == message.id
      Box.find message.boxId, @redisStoreSettings, (err, box) ->
        box.lxcRoot = boxer.lxcRoot

        box.destroy (err) ->
          if !err
            destroyedMessage = new protocol.DestroyedMessage({id: boxer.id, boxId: box.id})
            boxer.publisher.publish boxer.coachChannel, destroyedMessage.encode()
