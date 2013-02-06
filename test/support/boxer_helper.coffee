Boxer                   = require '../../app/lib/boxer'
MessageParser           = require '../../app/lib/message_parser'
{ initRedisClientWith } = require '../../app/lib/utils'
settings                = require '../../config/settings'

module.exports = class BoxerHelper
  constructor: ->
    # hard-coded fixture
    @ip = '192.168.254.2'
    @name = 'mclovins-container'
    @id = 'test.action.io'
    @resource =
      gateway: '192.168.254.1',
      interface: 'br-lxc-254',
      port: '10000'

  setUp: ->
    @publisher = initRedisClientWith settings.redisMQ
    @coach = initRedisClientWith settings.redisStore

  # start a box with selected settings
  runBox: (done) ->
    @boxer = new Boxer(settings)
    @boxer.run done

  setupRedis: (done) ->
    cleanDB =>
      multi = @publisher.multi()
      multi.rpush 'aio:available_resources', @ip
      multi.hmset "aio:nwr:#{@ip}", @resource
      multi.exec (err, replies) -> done(err)

  tearDown: (done) ->
    @boxer?.cleanup()
    @coach?.unsubscribe()
    @publisher?.unsubscribe()
    @boxer = @coach = @publisher = null
    cleanupContainer 'mclovins-container-1', @ip, done

  publishSettings: (attributes) ->
    attributes.id ?= @id
    attributes.name ?= @name
    @publisher.publish settings.boxerChannel, JSON.stringify(attributes)

  # Helper to create a new box
  createBox: (attributes={}) ->
    attributes.type ?= 'aio:create'
    attributes.boxId ?= 1
    attributes.runtime ?= "test"
    attributes.memory ?= "256M"
    attributes.diskSpace ?= '1G'
    attributes.publicKeys ?= []
    attributes.snapshotURL ?= null
    @publishSettings attributes

  # wait for a specific message type from coach, when we get it, pass the
  # message to callback
  waitForMessage: (messageType, callback) ->
    @coach.on 'message', (channel, rawMessage) ->
      message = MessageParser.decode(rawMessage)
      if message.type == messageType
        callback message

  subscribeAndDo: (callback) ->
    @coach.subscribe settings.coachChannel, (err, result) ->
      throw err if err
      callback()
