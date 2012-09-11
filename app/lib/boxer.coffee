MessageParser = require './message_parser'
Box = require './box'
protocol = require '../protocol'
redis = require 'redis'

module.exports = class Boxer
  constructor: (settings)->
    @id = settings.id
    @runtimes = settings.runtimes
    @lxcRoot = settings.lxcRoot
    @containerIdleTime = settings.containerIdleTime

    @boxerChannel = settings.boxerChannel
    @coachChannel = settings.coachChannel

    @redisMQSettings = settings.redisMQ
    @redisStoreSettings = settings.redisStore

    @subscriber = redis.createClient(@redisMQSettings.port, @redisMQSettings.host)
    @subscriber.auth(@redisMQSettings.password) if @redisMQSettings.password?
    @subscriber.select(@redisMQSettings.database)
    # We need a separate client to publish events, since
    # once a redis client is in 'subscribe' mode,
    # it can't perform other operations
    @publisher = redis.createClient(@redisMQSettings.port, @redisMQSettings.host)
    @publisher.auth(@redisMQSettings.password) if @redisMQSettings.password?
    @publisher.select(@redisMQSettings.database)

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

    else if message.type == protocol.StartMessage.type
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
          startedMessage = new protocol.StartedMessage(
                                                       id: boxer.id
                                                       boxId: @id
                                                       ip: @ip
                                                       port: @port
                                                      )
          boxer.publisher.publish boxer.coachChannel, startedMessage.encode()

        # TODO: Implement the errCallback
        errCallback = (err) ->
          console.log "OMG ERROR"

        box.create successCallback, errCallback
    else if message.type == protocol.StopMessage.type && @id == message.id
      Box.find message.boxId, @redisStoreSettings, (err, box) ->
        box.stop (err) ->
          if !err
            stoppedMessage = new protocol.StoppedMessage({id: boxer.id, boxId: box.id})
            boxer.publisher.publish boxer.coachChannel, stoppedMessage.encode()
