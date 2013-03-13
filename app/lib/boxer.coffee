MessageParser = require './message_parser'
protocol = require '../protocol'
initRedisClientWith = require('./utils').initRedisClientWith
logger = require './logger'
settings = require '../../config/settings'
messageHandlers = require './message_handlers'

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
    @publisher.publish @coachChannel, advertiseMessage.encode()

  _handle: (message) ->
    logger.info "Received Message: #{message.type} | id: #{message.id}"
    for key, handler of messageHandlers
      break if handler(this, message) != false
