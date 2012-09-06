MessageParser = require './message_parser'
Box = require './box'
protocol = require '../protocol'
redis = require 'redis'

module.exports = class Boxer
  @BOXER_CHANNEL = 'aio-boxer-channel'
  @COACH_CHANNEL = 'aio-coach-channel'

  constructor: (settings)->
    @id = settings.id
    @runtimes = settings.runtimes
    @lxcRoot = settings.lxcRoot
    @containerIdleTime = settings.containerIdleTime

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

  run: ->
    boxer = this

    @subscriber.subscribe Boxer.BOXER_CHANNEL, (err, result) ->
      if !err
        boxer.subscriber.on 'message', (channel, rawMessage) ->
          boxer._handle(MessageParser.decode(rawMessage))


  _handle:(message) ->
    if message.type == protocol.LocateMessage.type
      @publisher.publish Boxer.COACH_CHANNEL, protocol.AdvertiseMessage.construct().encode()
    else if message.type == protocol.StartMessage.type
      if @id == message.id && (containerTemplate = @runtimes[message.runtime])?
        box = new Box(message.hostName, containerTemplate, message.memory, message.diskSpace, message.publicKeys, message.snapshotURL)
        box.create (err) ->

