MessageParser = require './message_parser'
protocol = require '../protocol'
redis = require 'redis'

module.exports = class Boxer
  @LOCATE_CHANNEL = 'aio-locate-channel'
  @ADVERTISE_CHANNEL = 'aio-advertise-channel'

  constructor: ->
    settings = require('../../config/settings').redis

    @subscriber = redis.createClient(settings.port, settings.host)
    @subscriber.auth(settings.password) if settings.password?
    @subscriber.select(settings.database)

    @publisher = redis.createClient(settings.port, settings.host)
    @publisher.auth(settings.password) if settings.password?
    @publisher.select(settings.database)

  run: ->
    boxer = this
    @subscriber.subscribe Boxer.LOCATE_CHANNEL, (err, result) ->
      if !err
        boxer.subscriber.on 'message', (channel, rawMessage) ->
          boxer._handle(MessageParser.decode(rawMessage))


  _handle:(message) ->
    if message.type == protocol.LocateMessage.type
      @publisher.publish Boxer.ADVERTISE_CHANNEL, protocol.AdvertiseMessage.construct().encode()


