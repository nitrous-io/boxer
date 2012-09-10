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

    redisSettings = settings.redisMQ

    @subscriber = redis.createClient(redisSettings.port, redisSettings.host)
    @subscriber.auth(redisSettings.password) if redisSettings.password?
    @subscriber.select(redisSettings.database)
    # We need a separate client to publish events, since
    # once a redis client is in 'subscribe' mode,
    # it can't perform other operations
    @publisher = redis.createClient(redisSettings.port, redisSettings.host)
    @publisher.auth(redisSettings.password) if redisSettings.password?
    @publisher.select(redisSettings.database)

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
    if message.type == protocol.LocateMessage.type
      @publisher.publish @coachChannel,
                         protocol.AdvertiseMessage.construct().encode()

    else if message.type == protocol.StartMessage.type
      if @id == message.id && (containerTemplate = @runtimes[message.runtime])?
        box = new Box(message.boxId,
                      message.hostName,
                      containerTemplate,
                      @lxcRoot,
                      message.memory,
                      message.diskSpace,
                      message.publicKeys,
                      message.snapshotURL)

        boxer = this

        box.create (err) ->
          startedMessage = new protocol.StartedMessage(
                                                       id: boxer.id
                                                       boxId: @id
                                                       ip: @ip
                                                       port: @port
                                                      )
          boxer.publisher.publish boxer.coachChannel, startedMessage.encode()

