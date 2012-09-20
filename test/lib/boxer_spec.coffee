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
    redisMQSettings = settings.redisMQ
    redisStoreSettings = settings.redisStore

  describe 'run', ->
    context 'aio:create', ->
      beforeEach (done) ->
        publisher = initRedisClientWith(redisMQSettings)
        coach = initRedisClientWith(redisMQSettings)

        cleanDB ->
          multi = publisher.multi()
          multi.rpush 'available_ips', '192.168.254.254'
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
        it 'should return an aio:created message with the requisite properties filled', (done) ->
          coach.subscribe settings.coachChannel, (err, result) ->
            if !err
              coach.on 'message', (channel, rawMessage) ->
                message = MessageParser.decode(rawMessage)

                root = "/var/lib/lxc/mclovins-container/rootfs"
                networkConfig = fs.readFileSync("#{root}/etc/network/interfaces")
                name = fs.readFileSync("#{root}/etc/hostname")
                publicKeys = fs.readFileSync("#{root}/etc/ssh/univ_public_keys").toString().trim().split("\n")

                expect(message.type).to.eql 'aio:created'
                expect(message.port).to.eql 10000
                expect(message.boxId).to.eql 1
                expect(message.id).to.eql 'test.action.io'
                expect(message.success).to.be.true
                expect(networkConfig).to.match /address 192.168.254.254/
                expect(name).to.match /mclovins-container/
                expect(publicKeys).to.eql ['public-key-1', 'public-key-2']

                childProcess.exec "sudo iptables -L -t nat", timeout: 5000, (err, stdout, stderr) ->
                  expect(stdout).to.match /192\.168\.254\.254:22/

                  publisher.hget 'aio:boxes', 'mclovins-container', (err, res) ->
                     msg = JSON.parse(res)
                     expect(msg.id).to.eql 1
                     expect(msg.name).to.eql 'mclovins-container'
                     expect(msg.ip).to.eql '192.168.254.254'
                     expect(msg.port).to.eql 10000
                     expect(msg.memory).to.eql '256'
                     expect(msg.diskSpace).to.eql '4096'
                     expect(msg.boxerId).to.eql 'test.action.io'
                     done(err)

              publisher.publish settings.boxerChannel,
                                '{"type":"aio:create",' +
                                '"id":"test.action.io",' +
                                '"boxId":1,' +
                                '"runtime":"test",' +
                                '"name":"mclovins-container",' +
                                '"memory":"256",' +
                                '"diskSpace":"4096",' +
                                '"publicKeys":["public-key-1","public-key-2"],' +
                                '"snapshotURL":null}'

      context 'unsuccessful provisioning', ->
        beforeEach ->
          sinon.stub Box.prototype, 'save', ->
            throw new Error("OMG")

        afterEach ->
          Box.prototype.save.restore()

        it 'should return an aio:created message with the success flag set to false', (done) ->
          coach.subscribe settings.coachChannel, (err, result) ->
            if !err
              coach.on 'message', (channel, rawMessage) ->
                message = MessageParser.decode(rawMessage)

                expect(message.type).to.eql 'aio:created'
                expect(message.boxId).to.eql 1
                expect(message.id).to.eql 'test.action.io'
                expect(message.success).to.eql false

                childProcess.exec "sudo iptables -L -t nat", timeout: 5000, (err, stdout, stderr) ->
                  expect(stdout).to.not.match /192\.168\.254\.254:22/

                  childProcess.exec "sudo lxc-info -n mclovins-container", timeout: 5000, (err, stdout, stderr) ->
                    expect(stdout).to.match /STOPPED/

                    publisher.hget 'aio:boxes', 'mclovins-container', (err, res) ->
                      expect(res).to.be.null
                      done(err)

              publisher.publish settings.boxerChannel,
                                '{"type":"aio:create",' +
                                '"id":"test.action.io",' +
                                '"boxId":1,' +
                                '"runtime":"test",' +
                                '"name":"mclovins-container",' +
                                '"memory":"256",' +
                                '"diskSpace":"4096",' +
                                '"publicKeys":[],' +
                                '"snapshotURL":null}'

      context 'invalid params', ->
        it 'should return an aio:created message (with the success flag set to false) and not create the container', (done) ->
          coach.subscribe settings.coachChannel, (err, result) ->
            if !err
              coach.on 'message', (channel, rawMessage) ->
                message = MessageParser.decode(rawMessage)

                expect(message.type).to.eql 'aio:created'
                expect(message.id).to.eql 'test.action.io'
                expect(message.success).to.eql false

                childProcess.exec "sudo iptables -L -t nat", timeout: 5000, (err, stdout, stderr) ->
                  expect(stdout).to.not.match /192\.168\.254\.254:22/

                  childProcess.exec "sudo lxc-info -n mclovins-container", timeout: 5000, (err, stdout, stderr) ->
                    expect(stdout).to.match /STOPPED/

                    publisher.hget 'aio:boxes', 'mclovins-container', (err, res) ->
                      expect(res).to.be.null
                      done(err)

              publisher.publish settings.boxerChannel,
                                '{"type":"aio:create",' +
                                '"id":"test.action.io",' +
                                '"runtime":"test",' +
                                '"name":"mclovins-container",' +
                                '"memory":"256",' +
                                '"diskSpace":"4096",' +
                                '"publicKeys":[],' +
                                '"snapshotURL":null}'


    context 'aio:locate', ->
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

      it 'should return an aio:advertise message with the boxer\'s capabilities', (done) ->
        coach.subscribe settings.coachChannel, (err, result) ->
          if !err
            coach.on 'message', (channel, rawMessage) ->
              message = MessageParser.decode(rawMessage)
              expect(message.type).to.eql 'aio:advertise'
              expect(message.id).to.eql 'test.action.io'
              expect(message.freeMemory).to.exist
              done()

            publisher.publish settings.boxerChannel, '{"type":"aio:locate"}'

    context 'aio:stop', ->
      before (done) ->
        coach = initRedisClientWith(redisMQSettings)
        publisher = initRedisClientWith(redisMQSettings)

        childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container", timeout:5000, (err, stdout, stderr) ->
          if !err
            cleanDB ->
              publisher.hset 'aio:boxes', "mclovins-container", '{"id":1,"name":"mclovins-container"}'
              boxer = new Boxer(settings)
              boxer.run(done)

      after (done) ->
        publisher.unsubscribe()
        coach.unsubscribe()
        boxer.cleanup()

        coach = publisher = boxer = null
        cleanupContainer(done)

      it 'should return an aio:stopped message with the box\'s id present', (done) ->
        coach.subscribe settings.coachChannel, (err, result) ->
          if !err
            coach.on 'message', (channel, rawMessage) ->
              message = MessageParser.decode(rawMessage)
              expect(message.type).to.eql 'aio:stopped'
              expect(message.id).to.eql 'test.action.io'
              expect(message.boxId).to.eql 1

              childProcess.exec "sudo lxc-info -n mclovins-container", timeout: 5000, (err, stdout, stderr) ->
                expect(stdout).to.match /STOPPED/
                done(err)

            publisher.publish settings.boxerChannel, '{"type":"aio:stop","id":"test.action.io","name":"mclovins-container"}'

    context 'aio:start' , ->
      before (done) ->
        publisher = initRedisClientWith(redisMQSettings)
        coach = initRedisClientWith(redisMQSettings)

        childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container dont-start", timeout:5000, (err, stdout, stderr) ->
          if !err
            cleanDB ->
              publisher.hset 'aio:boxes', "mclovins-container", '{"id":1,"name":"mclovins-container","ip":"192.168.254.254","port":10000}'
              boxer = new Boxer(settings)
              boxer.run(done)

      after (done) ->
        boxer.cleanup()
        coach.unsubscribe()
        publisher.unsubscribe()

        boxer = coach = publisher = null
        cleanupContainer(done)

      it 'should start an already created container', (done) ->
        coach.subscribe settings.coachChannel, (err, result) ->
          if !err
            coach.on 'message', (channel, rawMessage) ->
              message = MessageParser.decode(rawMessage)
              expect(message.type).to.eql 'aio:started'
              expect(message.id).to.eql 'test.action.io'
              expect(message.boxId).to.eql 1

              childProcess.exec "sudo lxc-info -n mclovins-container", timeout: 5000, (err, stdout, stderr) ->
                expect(stdout).to.match /RUNNING/
                done()

            publisher.publish settings.boxerChannel, '{"type":"aio:start","id":"test.action.io","name":"mclovins-container"}'

    context 'aio:configure', ->
      publicKeysFile = "/var/lib/lxc/mclovins-container/rootfs/etc/ssh/univ_public_keys"

      beforeEach (done) ->
        publisher = initRedisClientWith(redisMQSettings)
        coach = initRedisClientWith(redisMQSettings)

        childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container", timeout:5000, (err, stdout, stderr) ->
          if !err
            cleanDB ->
              publisher.hset 'aio:boxes', "mclovins-container", '{"id":1,"name":"mclovins-container","ip":"192.168.254.254","port":10000}'
              boxer = new Boxer(settings)
              boxer.run(done)

      afterEach (done) ->
        boxer.cleanup()
        coach.unsubscribe()
        publisher.unsubscribe()

        boxer = coach = publisher = null
        cleanupContainer(done)

      context 'adding public keys', ->
        it 'should add a public key to the box', (done) ->
          coach.subscribe settings.coachChannel, (err, result) ->
            if !err
              coach.on 'message', (channel, rawMessage) ->
                message = MessageParser.decode(rawMessage)
                expect(message.type).to.eql 'aio:configured'
                expect(message.id).to.eql 'test.action.io'
                expect(message.boxId).to.eql 1

                output = fs.readFileSync(publicKeysFile).toString().trim()

                expect(fs.existsSync(publicKeysFile)).to.be.true
                expect(output).to.eql 'public-key'
                done()

              publisher.publish settings.boxerChannel, '{"type":"aio:configure","id":"test.action.io","name":"mclovins-container","dataType":"aio:configure:add_public_key","data":{"publicKey":"public-key"}}'

      context 'removing public keys', ->
        beforeEach (done) ->
          childProcess.exec "sudo scripts/boxer-add-public-keys '/var/lib/lxc' 'mclovins-container' 'public-key'", timeout: 5000, (err, stdout, stderr) ->
            done() if !err

        it 'should remove the public key from the box', (done) ->
          coach.subscribe settings.coachChannel, (err, result) ->
            if !err
              coach.on 'message', (channel, rawMessage) ->
                message = MessageParser.decode(rawMessage)
                expect(message.type).to.eql 'aio:configured'
                expect(message.id).to.eql 'test.action.io'
                expect(message.boxId).to.eql 1

                publicKeysFile = "/var/lib/lxc/mclovins-container/rootfs/etc/ssh/univ_public_keys"
                output = fs.readFileSync(publicKeysFile).toString().trim()

                expect(fs.existsSync(publicKeysFile)).to.be.true
                expect(output).to.eql ''
                done()

              console.log "Going to Publish Message"
              publisher.publish settings.boxerChannel, '{"type":"aio:configure","id":"test.action.io","name":"mclovins-container","dataType":"aio:configure:remove_public_key","data":{"publicKey":"public-key"}}'


    context 'aio:destroy', ->
      before (done) ->
        publisher = initRedisClientWith(redisMQSettings)
        coach = initRedisClientWith(redisMQSettings)

        childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container", timeout:5000, (err, stdout, stderr) ->
          if !err
            childProcess.exec "sudo lxc-stop -n mclovins-container", timeout: 5000, (err, stdout, stderr) ->
              cleanDB ->
                publisher.hset 'aio:boxes', "mclovins-container", '{"id":1,"name":"mclovins-container","ip":"192.168.254.254","port":10000}'
                boxer = new Boxer(settings)
                boxer.run(done)

      after (done) ->
        boxer.cleanup()
        coach.unsubscribe()
        publisher.unsubscribe()

        boxer = coach = publisher = null
        cleanupContainer(done)

      it 'should destroy the container and remove all remnants', (done) ->
        coach.subscribe settings.coachChannel, (err, result) ->
          if !err
            coach.on 'message', (channel, rawMessage) ->
              message = MessageParser.decode(rawMessage)
              expect(message.type).to.eql 'aio:destroyed'
              expect(message.id).to.eql 'test.action.io'
              expect(message.boxId).to.eql 1

              expect(fs.existsSync("/var/lib/lxc/mclovins-container")).to.be.false
              expect(fs.existsSync("/var/lib/lxc/mclovins-container-delta")).to.be.false

              childProcess.exec "sudo iptables -L -t nat", timeout: 5000, (err, stdout, stderr) ->
                expect(stdout).to.not.match /192\.168\.254\.254:22/

                childProcess.exec "sudo lxc-info -n mclovins-container", timeout: 5000, (err, stdout, stderr) ->
                  expect(stdout).to.match /STOPPED/

                  publisher.hget 'aio:boxes', 'mclovins-container', (err, res) ->
                    expect(res).to.be.null
                    done()

            publisher.publish settings.boxerChannel, '{"type":"aio:destroy","id":"test.action.io","name":"mclovins-container"}'
