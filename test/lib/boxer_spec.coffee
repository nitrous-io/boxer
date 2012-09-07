Boxer = require '../../app/lib/boxer'
MessageParser = require '../../app/lib/message_parser'
redis = require 'redis'

describe 'Boxer', ->
  subscriber = publisher = settings = null

  beforeEach ->
    settings = require('../../config/settings')
    redisSettings = settings.redisMQ

    subscriber = redis.createClient(redisSettings.port, redisSettings.host)
    subscriber.auth(redisSettings.password) if redisSettings.password?
    subscriber.select(redisSettings.database)

    publisher = redis.createClient(redisSettings.port, redisSettings.host)
    publisher.auth(redisSettings.password) if redisSettings.password?
    publisher.select(redisSettings.database)


  describe 'run', ->
    context 'listening to aio.locate', ->
      boxer = null

      beforeEach (done) ->
        boxer = new Boxer(settings)
        boxer.run()
        cleanDB(done)

      it 'should return an aio.advertise message', (done) ->
        subscriber.subscribe 'aio-coach-channel', (err, result) =>
          if !err
            subscriber.on 'message', (channel, rawMessage) ->
              message = MessageParser.decode(rawMessage)
              message.type.should.eql 'aio.advertise'
              message.id.should.not.be.empty
              done()

            publisher.publish 'aio-boxer-channel', '{"type":"aio.locate"}'
          else
            throw err

    #context 'listening to aio.start', ->
      #beforeEach ->
        #@settings.id = 'boxer-id'
        #@settings.runtimes = {'test':'test-warden-container'}

        #@boxer = new Boxer(@settings)
        #@boxer.run()

      #context 'without a box which has not been archived', ->
        #context 'when the ID does match the box\'s ID', ->
          #@publisher.publish 'aio-start-channel', '{"type":"aio.start"}'
