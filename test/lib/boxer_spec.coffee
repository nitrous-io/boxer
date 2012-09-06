Boxer = require '../../app/lib/boxer'
MessageParser = require '../../app/lib/message_parser'
redis = require 'redis'

describe 'Boxer', ->
  beforeEach ->
    settings = require('../../config/settings').redis

    @subscriber = redis.createClient(settings.port, settings.host)
    @subscriber.auth(settings.password) if settings.password?
    @subscriber.select(settings.database)

    @publisher = redis.createClient(settings.port, settings.host)
    @publisher.auth(settings.password) if settings.password?
    @publisher.select(settings.database)

  describe 'run', ->
    context 'listening to aio.locate', ->
      beforeEach ->
        @boxer = new Boxer
        @boxer.run()

      it 'should return an aio.advertise message', (done) ->
        @subscriber.subscribe 'aio-advertise-channel', (err, result) =>
          if !err
            @subscriber.on 'message', (channel, rawMessage) ->
              message = MessageParser.decode(rawMessage)
              message.type.should.eql 'aio.advertise'
              message.id.should.not.be.empty
              done()

            @publisher.publish 'aio-locate-channel', '{"type":"aio.locate"}'
          else
            throw err

