Boxer = require '../../app/lib/boxer'
MessageParser = require '../../app/lib/message_parser'
redis = require 'redis'
childProcess = require 'child_process'
fs = require 'fs'
_ = require 'underscore'

scriptPath = __dirname.replace('test/lib', 'scripts/')

describe 'Boxer', ->
  subscriber = publisher = settings = redisSettings = null

  before ->
    settings = require('../../config/settings')
    settings.id = 'boxer-id'
    redisSettings = settings.redisMQ

    subscriber = redis.createClient(redisSettings.port, redisSettings.host)
    subscriber.select(redisSettings.database)

    publisher = redis.createClient(redisSettings.port, redisSettings.host)
    publisher.select(redisSettings.database)

  after (done) ->
    command = _.flatten([
                          "sudo"
                          "#{scriptPath}boxer-cleanup-tests",
                        ]).join(' ').trim()

    childProcess.exec command, timeout: 5000, (err, stdout, stderr) ->
      done(err)

  describe 'run', ->
    context 'aio.start', ->
      before (done) ->
        cleanDB ->
          multi = publisher.multi()
          multi.rpush 'available_ips', '254'
          multi.rpush 'available_ports', '10000'
          multi.exec (err, replies) ->
            boxer = new Boxer(settings)
            boxer.run(done)

      after ->
        subscriber.punsubscribe()

      it 'should return an aio.started message with the requisite properties filled', (done) ->
        subscriber.subscribe settings.coachChannel, (err, result) ->
          if !err
            subscriber.on 'message', (channel, rawMessage) ->
              message = MessageParser.decode(rawMessage)

              root = "/var/lib/lxc/mclovins-container/rootfs"
              networkConfig = fs.readFileSync("#{root}/etc/network/interfaces")
              hostName = fs.readFileSync("#{root}/etc/hostname")

              expect(message.type).to.eql 'aio.started'
              expect(message.ip).to.eql '192.168.254.254'
              expect(message.port).to.eql 10000
              expect(message.boxId).to.eql 1
              expect(message.id).to.eql 'boxer-id'
              expect(networkConfig).to.match /address 192.168.254.254/
              expect(hostName).to.match /mclovins-container/

              childProcess.exec "sudo iptables -L -t nat", timeout: 5000, (err, stdout, stderr) ->
                expect(stdout).to.match /192\.168\.254\.254:22/

                childProcess.exec "sudo lxc-info -n mclovins-container", timeout: 5000, (err, stdout, stderr) ->
                  expect(stdout).to.match /RUNNING/
                  done(err)

            publisher.publish settings.boxerChannel,
                              '{"type":"aio.start",' +
                              '"id":"boxer-id",' +
                              '"boxId":1,' +
                              '"runtime":"test",' +
                              '"hostName":"mclovins-container",' +
                              '"memory":"256",' +
                              '"diskSpace":"4096",' +
                              '"publicKeys":[],' +
                              '"snapshotURL":null}'


    context 'aio.locate', ->
      before (done) ->
        cleanDB ->
          boxer = new Boxer(settings)
          boxer.run(done)

      after ->
        subscriber.punsubscribe()

      it 'should return an aio.advertise message with the boxer\'s capabilities', ->
        subscriber.subscribe settings.coachChannel, (err, result) ->
          if !err
            subscriber.on 'message', (channel, rawMessage) ->
              message = MessageParser.decode(rawMessage)
              expect(message.type).to.eql 'aio.advertise'
              expect(message.id).to.eql 'boxer-id'
              expect(message.freeMemory).to.exist()

            publisher.publish settings.boxerChannel, '{"type":"aio.locate"}'

