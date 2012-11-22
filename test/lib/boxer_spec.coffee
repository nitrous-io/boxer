Boxer               = require '../../app/lib/boxer'
Box                 = require '../../app/lib/box'
MessageParser       = require '../../app/lib/message_parser'
initRedisClientWith = require('../../app/lib/utils').initRedisClientWith
childProcess        = require 'child_process'
fs                  = require 'fs'
_                   = require 'underscore'
scriptPath          = __dirname.replace('test/lib', 'scripts/')

describe 'Boxer', ->
  boxer = coach = publisher = settings = redisMQSettings = redisStoreSettings = null

  publishSettings = (attributes) ->
    attributes.id ?= 'test.action.io'
    attributes.name ?= 'mclovins-container'
    publisher.publish settings.boxerChannel, JSON.stringify(attributes)

  # Helper to create a new box
  createBox = (attributes={}) ->
    attributes.type ?= 'aio:create'
    attributes.boxId ?= 1
    attributes.runtime ?= "test"
    attributes.memory ?= "256"
    attributes.diskSpace ?= '4096'
    attributes.publicKeys ?= []
    attributes.snapshotURL ?= null
    publishSettings attributes

  # start a box with selected settings
  runBox = (andDone) ->
    boxer = new Boxer(settings)
    boxer.run andDone

  # wait for a specific message type from coach, when we get it, pass the
  # message to callback
  waitForMessage = (messageType, callback) ->
    coach.on 'message', (channel, rawMessage) ->
      message = MessageParser.decode(rawMessage)
      if message.type == messageType
        callback message

  subscribeAndDo = (callback) ->
    coach.subscribe settings.coachChannel, (err, result) ->
      throw err if err
      callback()


  before ->
    settings = require('../../config/settings')
    redisMQSettings = settings.redisMQ
    redisStoreSettings = settings.redisStore

  beforeEach ->
    @timeout(10000)
    publisher = initRedisClientWith(redisMQSettings)
    coach = initRedisClientWith(redisMQSettings)

  afterEach (andDone) ->
    boxer.cleanup() if boxer
    coach.unsubscribe() if coach
    publisher.unsubscribe() if publisher
    boxer = coach = publisher = null
    cleanupContainer andDone

  describe 'run', ->
    describe 'aio:create', ->
      beforeEach (done) ->
        cleanDB ->
          multi = publisher.multi()
          multi.rpush 'available_ips', '192.168.254.2'
          multi.rpush 'available_ports', '10000'
          multi.exec (err, replies) ->
            return done(err) if err
            runBox done

      context 'successfully provisioned', ->
        it 'should return an aio:created message with the requisite properties filled', (done) ->
          assertMessage = (message) ->
            root = "/var/lib/lxc/mclovins-container/rootfs"
            networkConfig = fs.readFileSync("#{root}/etc/network/interfaces")
            name = fs.readFileSync("#{root}/etc/hostname")
            publicKeys = fs.readFileSync("#{root}/etc/ssh/univ_public_keys").toString().trim().split("\n")
            fstab = fs.readFileSync("/etc/fstab").toString()

            expect(message.port).to.eql 10000
            expect(message.boxId).to.eql 1
            expect(message.id).to.eql 'test.action.io'
            expect(message.success).to.be.true
            expect(networkConfig).to.match /address 192.168.254.2/
            expect(name).to.match /mclovins-container/
            expect(fstab).to.match /mclovins-container/
            expect(publicKeys).to.eql ['public-key-1', 'public-key-2']

            childProcess.exec "sudo iptables -L -t nat", timeout: 5000, (err, stdout, stderr) ->
              expect(stdout).to.match /192\.168\.254\.2:22/

              publisher.hget 'aio:boxes', 'mclovins-container', (err, res) ->
                msg = JSON.parse(res)
                expect(msg.id).to.eql 1
                expect(msg.name).to.eql 'mclovins-container'
                expect(msg.ip).to.eql '192.168.254.2'
                expect(msg.port).to.eql 10000
                expect(msg.memory).to.eql '256'
                expect(msg.diskSpace).to.eql '4096'
                expect(msg.boxerId).to.eql 'test.action.io'
                done(err)

          subscribeAndDo ->
            waitForMessage 'aio:created', assertMessage
            createBox publicKeys: ["public-key-1", "public-key-2"]

      context 'unsuccessful provisioning', ->
        beforeEach ->
          sinon.stub Box.prototype, 'save', -> throw new Error("OMG")

        afterEach ->
          Box.prototype.save.restore()

        it 'should return an aio:created message with the success flag set to false', (done) ->
          assertMessage = (message) ->
            expect(message.boxId).to.eql 1
            expect(message.id).to.eql 'test.action.io'
            expect(message.success).to.eql false

            childProcess.exec "sudo iptables -L -t nat", timeout: 5000, (err, stdout, stderr) ->
              expect(stdout).to.not.match /192\.168\.254\.2:22/

              childProcess.exec "sudo lxc-info -n mclovins-container", timeout: 5000, (err, stdout, stderr) ->
                expect(stdout).to.match /STOPPED/

                publisher.hget 'aio:boxes', 'mclovins-container', (err, res) ->
                  expect(res).to.be.null
                  done(err)

          subscribeAndDo ->
            waitForMessage 'aio:created', assertMessage
            createBox()

      context 'no resources available on redis', ->
        beforeEach (andDone) -> cleanDB andDone

        it 'should return an aio:created message (with the success flag set to false) and not create the container', (done) ->
          assertMessage = (message) ->
            expect(message.id).to.eql 'test.action.io'
            expect(message.success).to.eql false

            childProcess.exec "sudo iptables -L -t nat", timeout: 5000, (err, stdout, stderr) ->
              expect(stdout).to.not.match /192\.168\.254\.2:22/

              childProcess.exec "sudo lxc-info -n mclovins-container", timeout: 5000, (err, stdout, stderr) ->
                expect(stdout).to.match /STOPPED/

                publisher.hget 'aio:boxes', 'mclovins-container', (err, res) ->
                  expect(res).to.be.null
                  done(err)
          subscribeAndDo ->
            waitForMessage 'aio:created', assertMessage
            createBox()

      context 'invalid params', ->
        it 'should return an aio:created message (with the success flag set to false) and not create the container', (done) ->
          assertMessage = (message) ->
            expect(message.id).to.eql 'test.action.io'
            expect(message.success).to.eql false

            childProcess.exec "sudo iptables -L -t nat", timeout: 5000, (err, stdout, stderr) ->
              expect(stdout).to.not.match /192\.168\.254\.2:22/

              childProcess.exec "sudo lxc-info -n mclovins-container", timeout: 5000, (err, stdout, stderr) ->
                expect(stdout).to.match /STOPPED/

                publisher.hget 'aio:boxes', 'mclovins-container', (err, res) ->
                  expect(res).to.be.null
                  done(err)

          subscribeAndDo ->
            waitForMessage 'aio:created', assertMessage
            publishSettings type: "aio:create", runtime: 'test'

    describe 'aio:locate', ->
      beforeEach (andDone) -> cleanDB -> runBox andDone

      it 'should return an aio:advertise message with the boxer\'s capabilities', (done) ->
        assertMessage = (message) ->
          expect(message.id).to.eql 'test.action.io'
          expect(message.freeMemory).to.exist
          done()
        subscribeAndDo ->
          waitForMessage 'aio:advertise', assertMessage
          publishSettings type: "aio:locate"

    describe 'aio:stop', ->
      beforeEach (done) ->
        childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container", timeout:5000, (err, stdout, stderr) ->
          return done(err) if err
          cleanDB ->
            publisher.hset 'aio:boxes', "mclovins-container", '{"id":1,"name":"mclovins-container"}'
            runBox done

      it 'should return an aio:stopped message with the box\'s id present', (done) ->
        assertMessage = (message) ->
          expect(message.id).to.eql 'test.action.io'
          expect(message.boxId).to.eql 1
          expect(fs.existsSync("/etc/lxc/auto/mclovins-container.conf")).to.be.false

          childProcess.exec "sudo lxc-info -n mclovins-container", timeout: 5000, (err, stdout, stderr) ->
            expect(stdout).to.match /STOPPED/
            done(err)

        subscribeAndDo ->
          waitForMessage 'aio:stopped', assertMessage
          publishSettings type: "aio:stop"

    describe 'aio:start' , ->
      beforeEach (done) ->
        childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container dont-start", timeout:5000, (err, stdout, stderr) ->
          return done(err) if err
          cleanDB ->
            publisher.hset 'aio:boxes', "mclovins-container", '{"id":1,"name":"mclovins-container","ip":"192.168.254.2","port":10000}'
            runBox done

      it 'should start an already created container', (done) ->
        assertMessage = (message) ->
          expect(message.id).to.eql 'test.action.io'
          expect(message.boxId).to.eql 1
          symlink = fs.readFileSync("/etc/lxc/auto/mclovins-container.conf").toString()
          originalFile = fs.readFileSync("/var/lib/lxc/mclovins-container/config").toString()

          expect(symlink).to.eql(originalFile)

          childProcess.exec "sudo lxc-info -n mclovins-container", timeout: 5000, (err, stdout, stderr) ->
            expect(stdout).to.match /RUNNING/
            done()

        subscribeAndDo ->
          waitForMessage 'aio:started', assertMessage
          publishSettings type: "aio:start"

    describe 'aio:configure', ->
      publicKeysFile = "/var/lib/lxc/mclovins-container/rootfs/etc/ssh/univ_public_keys"
      publicKey = null

      beforeEach (done) ->
        childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container", timeout:5000, (err, stdout, stderr) ->
          return done(err) if err
          cleanDB ->
            publisher.hset 'aio:boxes', "mclovins-container", '{"id":1,"name":"mclovins-container","ip":"192.168.254.2","port":10000}'
            runBox done

      context 'adding public keys', ->
        beforeEach ->
          publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAp6hXfpITGpfV1pFsZu+om4aBiSnyPNfh+j/f815yOZ9tAbkYL7C5hw+1Vf6fpNy6Pj7nuleJpRHa5PVj49ObSij33quW+74di5YxfxhTTXfKCLso/YT0WnVBkS3wef7FkG71yx7WgL4zqm+65VXeL186zxCMEHNhn0LMb0T7Rqc8diHsbdYTa7KvtMNbunS196puZtthhp0TPi3VJKfJ94OYgECqbxEfdKsmwaxZzt1ECw8QKJG9xt8vzhw45t0W4073xBRYcMYa++QxZvqkQeoD2LiK9UDdjCGwku562oRjp4rbmQoznFw22zMmTdDuJx6pxpyaOi749CNzqwzV/Q== arun@iPhone"

        it 'should add a public key to the box', (done) ->
          assertMessage = (message) ->
            expect(message.id).to.eql 'test.action.io'
            expect(message.boxId).to.eql 1

            output = fs.readFileSync(publicKeysFile).toString().trim()

            expect(fs.existsSync(publicKeysFile)).to.be.true
            expect(output).to.eql publicKey
            done()

          subscribeAndDo ->
            waitForMessage 'aio:configured', assertMessage
            publishSettings type: "aio:configure", dataType: "aio:configure:add_public_key", data: publicKey

      context 'removing public keys', ->
        beforeEach (done) ->
          publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAp6hXfpITGpfV1pFsZu+om4aBiSnyPNfh+j/f815yOZ9tAbkYL7C5hw+1Vf6fpNy6Pj7nuleJpRHa5PVj49ObSij33quW+74di5YxfxhTTXfKCLso/YT0WnVBkS3wef7FkG71yx7WgL4zqm+65VXeL186zxCMEHNhn0LMb0T7Rqc8diHsbdYTa7KvtMNbunS196puZtthhp0TPi3VJKfJ94OYgECqbxEfdKsmwaxZzt1ECw8QKJG9xt8vzhw45t0W4073xBRYcMYa++QxZvqkQeoD2LiK9UDdjCGwku562oRjp4rbmQoznFw22zMmTdDuJx6pxpyaOi749CNzqwzV/Q== arun@iPhone"
          childProcess.exec "sudo scripts/boxer-add-public-keys '/var/lib/lxc' 'mclovins-container' '#{publicKey}'", timeout: 5000, (err, stdout, stderr) ->
            if err then throw err else done()

        it 'should remove the public key from the box', (done) ->
          assertMessage = (message) ->
            expect(message.id).to.eql 'test.action.io'
            expect(message.boxId).to.eql 1

            publicKeysFile = "/var/lib/lxc/mclovins-container/rootfs/etc/ssh/univ_public_keys"
            output = fs.readFileSync(publicKeysFile).toString().trim()

            expect(fs.existsSync(publicKeysFile)).to.be.true
            expect(output).to.eql ''
            done()

          subscribeAndDo ->
            waitForMessage 'aio:configured', assertMessage
            publishSettings type: "aio:configure", dataType: "aio:configure:remove_public_key", data: publicKey

      context 'setting env variables', ->
        it 'sets the variables to /etc/profile', (done) ->
          assertMessage = (message) ->
            profile = "/var/lib/lxc/mclovins-container/rootfs/etc/profile"
            profileContent = fs.readFileSync(profile).toString()
            expect(profileContent).to.contain 'export RDS_HOST=mysql://insecure'
            expect(profileContent).to.contain 'export RDS_PASSWORD=mysql-insecure'
            done()

          subscribeAndDo ->
            waitForMessage 'aio:configured', assertMessage
            publishSettings
              type: "aio:configure"
              dataType: "aio:configure:set_env_variables",
              data: {
                'RDS_HOST': "mysql://insecure",
                'RDS_PASSWORD': 'mysql-insecure'
              }


    describe 'aio:destroy', ->
      beforeEach (done) ->
        childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container", timeout:5000, (err, stdout, stderr) ->
          return done(err) if err
          childProcess.exec "sudo #{scriptPath}/boxer-stop-container mclovins-container", timeout: 5000, (err, stdout, stderr) ->
            cleanDB ->
              publisher.hset 'aio:boxes', "mclovins-container", '{"id":1,"name":"mclovins-container","ip":"192.168.254.2","port":10000}'
              runBox done

      it 'should destroy the container and remove all remnants', (done) ->
        assertMessage = (message) ->
          expect(message.id).to.eql 'test.action.io'
          expect(message.boxId).to.eql 1

          expect(fs.existsSync("/var/lib/lxc/mclovins-container")).to.be.false
          expect(fs.existsSync("/var/lib/lxc/mclovins-container_delta")).to.be.false
          expect(fs.readFileSync("/etc/fstab").toString()).to.not.match /mclovins-container/

          childProcess.exec "sudo iptables -L -t nat", timeout: 5000, (err, stdout, stderr) ->
            expect(stdout).to.not.match /192\.168\.254\.254:22/

            childProcess.exec "sudo lxc-info -n mclovins-container", timeout: 5000, (err, stdout, stderr) ->
              expect(stdout).to.match /STOPPED/

              publisher.hget 'aio:boxes', 'mclovins-container', (err, res) ->
                expect(res).to.be.null
                done()

        subscribeAndDo ->
          waitForMessage 'aio:destroyed', assertMessage
          publishSettings type: "aio:destroy"
