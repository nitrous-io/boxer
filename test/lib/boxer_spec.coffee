Boxer = require '../../app/lib/boxer'
Box = require '../../app/lib/box'
MessageParser = require '../../app/lib/message_parser'
childProcess = require 'child_process'
initRedisClientWith = require('../../app/lib/utils').initRedisClientWith
fs = require 'fs'
_ = require 'underscore'

scriptPath = __dirname.replace('test/lib', 'scripts/')

describe 'Boxer', ->
  boxer = coach = publisher = settings = redisMQSettings = redisStoreSettings = null

  before ->
    settings = require('../../config/settings')
    settings.id = 'boxer-id'
    redisMQSettings = settings.redisMQ
    redisStoreSettings = settings.redisStore

  describe 'run', ->
    context 'aio.create', ->
      beforeEach (done) ->
        publisher = initRedisClientWith(redisMQSettings)
        coach = initRedisClientWith(redisMQSettings)

        cleanDB ->
          multi = publisher.multi()
          multi.rpush 'available_ips', '254'
          multi.rpush 'available_ports', '10000'
          multi.exec (err, replies) ->
            boxer = new Boxer(settings)
            boxer.run(done)

      afterEach (done) ->
        boxer.cleanup()
        coach.unsubscribe()
        publisher.unsubscribe()

        boxer = coach = publisher = null
        cleanupContainer(done)

      context 'successfully provisioned', ->
        it 'should return an aio.created message with the requisite properties filled', (done) ->
          this.timeout(0)

          coach.subscribe settings.coachChannel, (err, result) ->
            if !err
              coach.on 'message', (channel, rawMessage) ->
                message = MessageParser.decode(rawMessage)

                root = "/var/lib/lxc/mclovins-container/rootfs"
                networkConfig = fs.readFileSync("#{root}/etc/network/interfaces")
                hostName = fs.readFileSync("#{root}/etc/hostname")

                expect(message.type).to.eql 'aio.created'
                expect(message.ip).to.eql '192.168.254.254'
                expect(message.port).to.eql 10000
                expect(message.boxId).to.eql 1
                expect(message.id).to.eql 'boxer-id'
                expect(message.success).to.be.true
                expect(networkConfig).to.match /address 192.168.254.254/
                expect(hostName).to.match /mclovins-container/

                childProcess.exec "sudo iptables -L -t nat", timeout: 5000, (err, stdout, stderr) ->
                  expect(stdout).to.match /192\.168\.254\.254:22/

                  childProcess.exec "sudo lxc-info -n mclovins-container", timeout: 5000, (err, stdout, stderr) ->
                    expect(stdout).to.match /RUNNING/

                    publisher.hget 'aio.boxes', 'mclovins-container', (err, res) ->
                       msg = JSON.parse(res)
                       expect(msg.id).to.eql 1
                       expect(msg.hostName).to.eql 'mclovins-container'
                       expect(msg.ip).to.eql '192.168.254.254'
                       expect(msg.port).to.eql 10000
                       expect(msg.memory).to.eql '256'
                       expect(msg.diskSpace).to.eql '4096'
                       done(err)

              publisher.publish settings.boxerChannel,
                                '{"type":"aio.create",' +
                                '"id":"boxer-id",' +
                                '"boxId":1,' +
                                '"runtime":"test",' +
                                '"hostName":"mclovins-container",' +
                                '"memory":"256",' +
                                '"diskSpace":"4096",' +
                                '"publicKeys":[],' +
                                '"snapshotURL":null}'

      context 'unsuccessful provisioning', ->
        beforeEach ->
          sinon.stub Box.prototype, '_startContainer', ->
            throw new Error("OMG")

        afterEach ->
          Box.prototype._startContainer.restore()

        it 'should return an aio.created message with the success flag set to false', (done) ->
          this.timeout(0)

          coach.subscribe settings.coachChannel, (err, result) ->
            if !err
              coach.on 'message', (channel, rawMessage) ->
                message = MessageParser.decode(rawMessage)

                expect(message.type).to.eql 'aio.created'
                expect(message.boxId).to.eql 1
                expect(message.id).to.eql 'boxer-id'
                expect(message.success).to.eql false

                childProcess.exec "sudo iptables -L -t nat", timeout: 5000, (err, stdout, stderr) ->
                  expect(stdout).to.not.match /192\.168\.254\.254:22/

                  childProcess.exec "sudo lxc-info -n mclovins-container", timeout: 5000, (err, stdout, stderr) ->
                    expect(stdout).to.match /STOPPED/

                    publisher.hget 'aio.boxes', 'mclovins-container', (err, res) ->
                      expect(res).to.be.null
                      done(err)

              publisher.publish settings.boxerChannel,
                                '{"type":"aio.create",' +
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
        publisher = initRedisClientWith(redisMQSettings)
        coach = initRedisClientWith(redisMQSettings)

        cleanDB ->
          boxer = new Boxer(settings)
          boxer.run(done)

      after ->
        coach.unsubscribe()
        publisher.unsubscribe()
        boxer.cleanup()

        boxer = coach = publisher = null

      it 'should return an aio.advertise message with the boxer\'s capabilities', (done) ->
        coach.subscribe settings.coachChannel, (err, result) ->
          if !err
            coach.on 'message', (channel, rawMessage) ->
              message = MessageParser.decode(rawMessage)
              expect(message.type).to.eql 'aio.advertise'
              expect(message.id).to.eql 'boxer-id'
              expect(message.freeMemory).to.exist
              done()

            publisher.publish settings.boxerChannel, '{"type":"aio.locate"}'

    context 'aio.stop', ->
      before (done) ->
        coach = initRedisClientWith(redisMQSettings)
        publisher = initRedisClientWith(redisMQSettings)

        settings.id = 'boxer-id'
        childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container", timeout:5000, (err, stdout, stderr) ->
          if !err
            cleanDB ->
              publisher.hset 'aio.boxes', "mclovins-container", '{"id":1,"hostName":"mclovins-container"}'
              boxer = new Boxer(settings)
              boxer.run(done)
          else
            console.log "Err -> #{stderr}"

      after (done) ->
        publisher.unsubscribe()
        coach.unsubscribe()
        boxer.cleanup()

        coach = publisher = boxer = null
        cleanupContainer(done)

      it 'should return an aio.stopped message with the box\'s id present', (done) ->
        this.timeout(0)

        coach.subscribe settings.coachChannel, (err, result) ->
          if !err
            coach.on 'message', (channel, rawMessage) ->
              message = MessageParser.decode(rawMessage)
              expect(message.type).to.eql 'aio.stopped'
              expect(message.id).to.eql 'boxer-id'
              expect(message.boxId).to.eql 1

              childProcess.exec "sudo lxc-info -n mclovins-container", timeout: 5000, (err, stdout, stderr) ->
                expect(stdout).to.match /STOPPED/
                done(err)

            publisher.publish settings.boxerChannel, '{"type":"aio.stop","id":"boxer-id","hostName":"mclovins-container"}'

    context 'aio.start' , ->
      before (done) ->
        publisher = initRedisClientWith(redisMQSettings)
        coach = initRedisClientWith(redisMQSettings)

        settings.id = 'boxer-id'
        childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container dont-start", timeout:5000, (err, stdout, stderr) ->
          if !err
            cleanDB ->
              publisher.hset 'aio.boxes', "mclovins-container", '{"id":1,"hostName":"mclovins-container","ip":"192.168.254.254","port":10000}'
              boxer = new Boxer(settings)
              boxer.run(done)

      after (done) ->
        boxer.cleanup()
        coach.unsubscribe()
        publisher.unsubscribe()

        boxer = coach = publisher = null
        cleanupContainer(done)

      it 'should start an already created container', (done) ->
        # This test might take a while
        this.timeout(0)

        coach.subscribe settings.coachChannel, (err, result) ->
          if !err
            coach.on 'message', (channel, rawMessage) ->
              message = MessageParser.decode(rawMessage)
              expect(message.type).to.eql 'aio.started'
              expect(message.id).to.eql 'boxer-id'
              expect(message.boxId).to.eql 1

              childProcess.exec "sudo lxc-info -n mclovins-container", timeout: 5000, (err, stdout, stderr) ->
                expect(stdout).to.match /RUNNING/
                done()

            publisher.publish settings.boxerChannel, '{"type":"aio.start","id":"boxer-id","hostName":"mclovins-container"}'

    context 'aio.destroy', ->
      before (done) ->
        publisher = initRedisClientWith(redisMQSettings)
        coach = initRedisClientWith(redisMQSettings)

        settings.id = 'boxer-id'
        childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container", timeout:5000, (err, stdout, stderr) ->
          if !err
            cleanDB ->
              publisher.hset 'aio.boxes', "mclovins-container", '{"id":1,"hostName":"mclovins-container","ip":"192.168.254.254","port":10000}'
              boxer = new Boxer(settings)
              boxer.run(done)

      after (done) ->
        boxer.cleanup()
        coach.unsubscribe()
        publisher.unsubscribe()

        boxer = coach = publisher = null
        cleanupContainer(done)

      it 'should destroy the container and remove all remnants', (done) ->
        # This test might take a while
        this.timeout(0)

        coach.subscribe settings.coachChannel, (err, result) ->
          if !err
            coach.on 'message', (channel, rawMessage) ->
              message = MessageParser.decode(rawMessage)
              expect(message.type).to.eql 'aio.destroyed'
              expect(message.id).to.eql 'boxer-id'
              expect(message.boxId).to.eql 1

              expect(fs.existsSync("/var/lib/lxc/mclovins-container")).to.be.false
              expect(fs.existsSync("/var/lib/lxc/mclovins-container-delta")).to.be.false

              childProcess.exec "sudo iptables -L -t nat", timeout: 5000, (err, stdout, stderr) ->
                expect(stdout).to.not.match /192\.168\.254\.254:22/

                childProcess.exec "sudo lxc-info -n mclovins-container", timeout: 5000, (err, stdout, stderr) ->
                  expect(stdout).to.match /STOPPED/

                  publisher.hget 'aio.boxes', 'mclovins-container', (err, res) ->
                    expect(res).to.be.null
                    done()

            publisher.publish settings.boxerChannel, '{"type":"aio.destroy","id":"boxer-id","hostName":"mclovins-container"}'
