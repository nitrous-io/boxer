Box                           = require '../../app/lib/box'
BoxerHelper                   = require '../support/boxer_helper'
{ assertStop, assertRunning } = require '../support/lxc_info'
{ getIps }                    = require '../support/network'
childProcess                  = require 'child_process'
fs                            = require 'fs'
_                             = require 'underscore'
scriptPath                    = __dirname.replace('test/integration', 'scripts')

describe 'Boxer', ->
  helper = publisher = null

  beforeEach ->
    @timeout(10000)
    helper = new BoxerHelper()
    helper.setUp()
    publisher = helper.publisher

  afterEach (andDone) ->
    helper.tearDown andDone

  describe 'aio:create', ->
    beforeEach (done) ->
      helper.setupRedis -> helper.runBox done

    it 'returns aio:created with the requisite properties when successfully provisioned', (done) ->
      assertMessage = (message) ->
        root = "/var/lib/lxc/mclovins-container-1/rootfs"
        networkConfig = fs.readFileSync("#{root}/etc/network/interfaces")
        name = fs.readFileSync("#{root}/etc/hostname")
        publicKeys = fs.readFileSync("#{root}/etc/ssh/univ_public_keys").toString().trim().split("\n")
        stats = fs.statSync("/#{root}/home/action")

        expect(message.port).to.eql 10000
        expect(message.boxId).to.eql 1
        expect(message.id).to.eql 'test.action.io'
        expect(message.success).to.be.true
        expect(networkConfig).to.match /address 192.168.254.2/
        expect(name).to.match /mclovins-container-1/
        expect(publicKeys).to.eql ['public-key-1', 'public-key-2']
        expect(fs.existsSync("/#{root}/home/action/.ssh")).to.be.true
        expect(fs.existsSync("/#{root}/home/action/workspace")).to.be.true

        expect(fs.existsSync("/#{root}/home/action/.ssh/id_rsa.pub")).to.be.true
        expect(fs.existsSync("/#{root}/home/action/.ssh/id_rsa")).to.be.true
        expect(fs.readFileSync("/#{root}/etc/passwd")).to.match /action:x:15001:15001/
        expect(fs.readFileSync("/var/lib/lxc/mclovins-container-1/config")).to.match /lxc.network.hwaddr = 02:00/
        expect(fs.readFileSync("/etc/projid")).to.match /mclovins-container-1:1/
        expect(fs.readFileSync("/etc/projects")).to.match /1:\/var\/lib\/lxc\/mclovins-container-1_delta\/rootfs\/home\/action/

        expect(stats.uid).to.eql 15001
        expect(stats.gid).to.eql 15001
        expect(fs.statSync("/#{root}/home/action/workspace").uid).to.eql 15001
        expect(fs.statSync("/#{root}/home/action/workspace").gid).to.eql 15001

        getIps (err, stdout, stderr) ->
          expect(stdout).to.match /192\.168\.254\.2:22/

          publisher.hget 'aio:boxes', 'mclovins-container-1', (err, res) ->
            msg = JSON.parse(res)
            expect(msg.id).to.eql 1
            expect(msg.name).to.eql 'mclovins-container'
            expect(msg.ip).to.eql '192.168.254.2'
            expect(msg.port).to.eql 10000
            expect(msg.memory).to.eql '256M'
            expect(msg.diskSpace).to.eql '1G'
            expect(msg.boxerId).to.eql 'test.action.io'
            expect(msg.containerState).to.eql 'stopped'
            done(err)

      helper.subscribeAndDo ->
        helper.waitForMessage 'aio:created', assertMessage
        helper.createBox publicKeys: ["public-key-1", "public-key-2"]

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

          getIps (err, stdout, stderr) ->
            expect(stdout).to.not.match /192\.168\.254\.2:22/

            assertStop 'mclovins-container-1', ->
              publisher.hget 'aio:boxes', 'mclovins-container-1', (err, res) ->
                expect(res).to.be.null
                done(err)

        helper.subscribeAndDo ->
          helper.waitForMessage 'aio:created', assertMessage
          helper.createBox()

    context 'no resources available on redis', ->
      beforeEach (andDone) -> cleanDB andDone

      it 'should return an aio:created message (with the success flag set to false) and not create the container', (done) ->
        assertMessage = (message) ->
          expect(message.id).to.eql 'test.action.io'
          expect(message.success).to.eql false

          getIps (err, stdout, stderr) ->
            expect(stdout).to.not.match /192\.168\.254\.2:22/

            assertStop 'mclovins-container-1', ->
              publisher.hget 'aio:boxes', 'mclovins-container-1', (err, res) ->
                expect(res).to.be.null
                done(err)

        helper.subscribeAndDo ->
          helper.waitForMessage 'aio:created', assertMessage
          helper.createBox()

    context 'invalid params', ->
      it 'should return an aio:created message (with the success flag set to false) and not create the container', (done) ->
        assertMessage = (message) ->
          expect(message.id).to.eql 'test.action.io'
          expect(message.success).to.eql false

          getIps (err, stdout, stderr) ->
            expect(stdout).to.not.match /192\.168\.254\.2:22/

            assertStop 'mclovins-container-1', ->
              publisher.hget 'aio:boxes', 'mclovins-container-1', (err, res) ->
                expect(res).to.be.null
                done(err)

        helper.subscribeAndDo ->
          helper.waitForMessage 'aio:created', assertMessage
          helper.publishSettings type: "aio:create", runtime: 'test'

  describe 'aio:locate', ->
    beforeEach (andDone) ->
      cleanDB -> helper.runBox andDone

    it 'should return an aio:advertise message with the boxer\'s capabilities', (done) ->
      assertMessage = (message) ->
        expect(message.id).to.eql 'test.action.io'
        expect(message.freeMemory).to.exist
        done()
      helper.subscribeAndDo ->
        helper.waitForMessage 'aio:advertise', assertMessage
        helper.publishSettings type: "aio:locate"

  describe 'aio:restart' , ->
    beforeEach (done) ->
      childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container 1 mclovins-container 192.168.254.2 10000", timeout:5000, (err, stdout, stderr) ->
        return done(err) if err
        cleanDB ->
          publisher.hset 'aio:boxes', "mclovins-container-1", '{"id":1,"name":"mclovins-container","ip":"192.168.254.2","port":10000,"diskSpace":"1G","memory":"256M","containerTemplate":"test_container_template","state":"running"}'
          helper.runBox done

    it 'should restart an already created container', (done) ->
      assertMessage = (message) ->
        expect(message.id).to.eql 'test.action.io'
        expect(message.boxId).to.eql 1
        expect(fs.readFileSync("/etc/projid")).to.match /mclovins-container-1:1/
        expect(fs.readFileSync("/etc/projects")).to.match /1:\/var\/lib\/lxc\/mclovins-container-1_delta\/rootfs\/home\/action/

        assertRunning 'mclovins-container-1', ->
          publisher.hget 'aio:boxes', 'mclovins-container-1', (err, res) ->
            msg = JSON.parse(res)
            expect(msg.id).to.eql 1
            expect(msg.name).to.eql 'mclovins-container'
            expect(msg.containerState).to.eql 'running'
            done(err)

      helper.subscribeAndDo ->
        helper.waitForMessage 'aio:restarted', assertMessage
        helper.publishSettings type: "aio:restart", name: "mclovins-container-1"

  describe 'aio:stop', ->
    beforeEach (done) ->
      childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container 1 mclovins-container 192.168.254.2 10000", timeout:5000, (err, stdout, stderr) ->
        return done(err) if err
        cleanDB ->
          publisher.hset 'aio:boxes', "mclovins-container-1", '{"id":1,"name":"mclovins-container","ip":"192.168.254.2","port":10000,"diskSpace":"1G","memory":"256M","containerTemplate":"test_container_template","containerState":"running"}'
          helper.runBox done

    it 'should return an aio:stopped message with the box\'s id present', (done) ->
      assertMessage = (message) ->
        expect(message.id).to.eql 'test.action.io'
        expect(message.boxId).to.eql 1
        expect(fs.existsSync("/var/lib/lxc/mclovins-container-1/rootfs")).to.be.false
        expect(fs.readFileSync("/etc/projid")).to.not.match /mclovins-container-1:1/
        expect(fs.readFileSync("/etc/projects")).to.not.match /1:\/var\/lib\/lxc\/mclovins-container-1_delta\/rootfs\/home\/action/

        assertStop 'mclovins-container-1', ->
          publisher.hget 'aio:boxes', 'mclovins-container-1', (err, res) ->
            msg = JSON.parse(res)
            expect(msg.id).to.eql 1
            expect(msg.name).to.eql 'mclovins-container'
            expect(msg.containerState).to.eql 'stopped'
            done(err)

      helper.subscribeAndDo ->
        helper.waitForMessage 'aio:stopped', assertMessage
        helper.publishSettings type: "aio:stop", name: "mclovins-container-1"

  describe 'aio:start' , ->
    beforeEach (done) ->
      childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container 1 mclovins-container 192.168.254.2 10000 dont-start", timeout:5000, (err, stdout, stderr) ->
        done(err) if err

        cleanDB ->
          publisher.hset 'aio:boxes', "mclovins-container-1", '{"id":1,"name":"mclovins-container","ip":"192.168.254.2","port":10000,"diskSpace":"1G","memory":"256M","containerTemplate":"test_container_template","containerState":"stopped"}'
          helper.runBox done

    it 'should start an already created container', (done) ->
      assertMessage = (message) ->
        expect(message.id).to.eql 'test.action.io'
        expect(message.boxId).to.eql 1

        assertRunning 'mclovins-container-1', ->
          publisher.hget 'aio:boxes', 'mclovins-container-1', (err, res) ->
            msg = JSON.parse(res)
            expect(msg.id).to.eql 1
            expect(msg.name).to.eql 'mclovins-container'
            expect(msg.containerState).to.eql 'running'
            done(err)

      helper.subscribeAndDo ->
        helper.waitForMessage 'aio:started', assertMessage
        helper.publishSettings type: "aio:start", name: "mclovins-container-1"

  describe 'aio:configure', ->
    publicKeysFile = "/var/lib/lxc/mclovins-container-1/rootfs/etc/ssh/univ_public_keys"
    publicKey = null

    beforeEach (done) ->
      childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container 1 mclovins-container 192.168.254.2 10000", timeout:5000, (err, stdout, stderr) ->
        done(err) if err
        cleanDB ->
          publisher.hset 'aio:boxes', "mclovins-container-1", '{"id":1,"name":"mclovins-container","ip":"192.168.254.2","port":10000,"diskSpace":"1G","memory":"256M","containerTemplate":"test_container_template"}'
          helper.runBox done

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

        helper.subscribeAndDo ->
          helper.waitForMessage 'aio:configured', assertMessage
          helper.publishSettings type: "aio:configure", dataType: "aio:configure:add_public_key", data: publicKey, name: "mclovins-container-1"

    context 'removing public keys', ->
      publicKey1 = publicKey2 = null

      beforeEach (done) ->
        publicKey1 = "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAp6hXfpITGpfV1pFsZu+om4aBiSnyPNfh+j/f815yOZ9tAbkYL7C5hw+1Vf6fpNy6Pj7nuleJpRHa5PVj49ObSij33quW+74di5YxfxhTTXfKCLso/YT0WnVBkS3wef7FkG71yx7WgL4zqm+65VXeL186zxCMEHNhn0LMb0T7Rqc8diHsbdYTa7KvtMNbunS196puZtthhp0TPi3VJKfJ94OYgECqbxEfdKsmwaxZzt1ECw8QKJG9xt8vzhw45t0W4073xBRYcMYa++QxZvqkQeoD2LiK9UDdjCGwku562oRjp4rbmQoznFw22zMmTdDuJx6pxpyaOi749CNzqwzV/Q== arun@iPhone"
        publicKey2 = "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAp6hXfpITGpfV1pFsZu+om4aBiSnyPNfh+j/f815yOZ9tAbkYL7C5hw+1Vf6fpNy6Pj7nuleJpRHa5PVj49ObSij33quW+74di5YxfxhTTXfKCLso/YT0WnVBkS3wef7FkG71yx7WgL4zqm+65VXeL186zxCMEHNhn0LMb0T7Rqc8diHsbdYTa7KvtMNbunS196puZtthhp0TPi3VJKfJ94OYgECqbxEfdKsmwaxZzt1ECw8QKJG9xt8vzhw45t0W4073xBRYcMYa++QxZvqkQeoD2LiK9UDdjCGwku562oRjp4rbmQoznFw22zMmTdDuJx6pxpyaOi749CNzqwzV/Q== arun@iPhone.local"

        childProcess.exec "sudo scripts/boxer-add-public-keys 'mclovins-container-1' '#{publicKey1}'", timeout: 5000, (err, stdout, stderr) ->
          if err
            throw err
          else
            childProcess.exec "sudo scripts/boxer-add-public-keys 'mclovins-container-1' '#{publicKey2}'", timeout: 5000, (err, stdout, stderr) ->
              if err then throw err else done()

      it 'should remove the public key from the box', (done) ->
        assertMessage = (message) ->
          expect(message.id).to.eql 'test.action.io'
          expect(message.boxId).to.eql 1
          publicKeysFile = "/var/lib/lxc/mclovins-container-1/rootfs/etc/ssh/univ_public_keys"
          output = fs.readFileSync(publicKeysFile).toString().trim()
          expect(fs.existsSync(publicKeysFile)).to.be.true
          expect(output).to.eql publicKey2
          done()

        helper.subscribeAndDo ->
          helper.waitForMessage 'aio:configured', assertMessage
          helper.publishSettings type: "aio:configure", dataType: "aio:configure:remove_public_key", data: publicKey1, name: "mclovins-container-1"

    context 'setting env variables', ->
      it 'sets the variables to /etc/profile', (done) ->
        assertMessage = (message) ->
          environmentFile = "/var/lib/lxc/mclovins-container-1/rootfs/etc/environment"
          env = fs.readFileSync(environmentFile).toString()
          expect(env).to.contain 'RDS_HOST=mysql://insecure'
          expect(env).to.contain 'RDS_PASSWORD=mysql-insecure'
          done()

        helper.subscribeAndDo ->
          helper.waitForMessage 'aio:configured', assertMessage
          helper.publishSettings
            type: "aio:configure"
            dataType: "aio:configure:set_env_variables",
            name: "mclovins-container-1",
            data: {
              'RDS_HOST': "mysql://insecure",
              'RDS_PASSWORD': 'mysql-insecure'
            }

    context 'setting env variables (with returnVars)', ->
      it 'sets the variables to /etc/profile', (done) ->
        assertMessage = (message) ->
          environmentFile = "/var/lib/lxc/mclovins-container-1/rootfs/etc/environment"
          env = fs.readFileSync(environmentFile).toString()
          expect(env).to.contain 'RDS_HOST=mysql://insecure'
          expect(env).to.contain 'RDS_PASSWORD=mysql-insecure'
          expect(message.returnVars).to.eql { 'addon_id': 1 }
          done()

        helper.subscribeAndDo ->
          helper.waitForMessage 'aio:configured', assertMessage
          helper.publishSettings
            type: "aio:configure"
            dataType: "aio:configure:set_env_variables",
            name: "mclovins-container-1",
            returnVars: {
              'addon_id': 1
            },
            data: {
              'RDS_HOST': "mysql://insecure",
              'RDS_PASSWORD': 'mysql-insecure'
            }

    context 'removing env variables', ->
      beforeEach (done) ->
        childProcess.exec "sudo scripts/boxer-set-env-variables 'mclovins-container-1' 'RDS_HOST=123'", timeout: 5000, (err, stdout, stderr) ->
          if err then throw err else done()

      it 'remove the variables from /etc/profile', (done) ->
        assertMessage = (message) ->
          environmentFile = "/var/lib/lxc/mclovins-container-1/rootfs/etc/environment"
          env = fs.readFileSync(environmentFile).toString()
          expect(env).to.not.contain 'RDS_HOST=123'
          done()

        helper.subscribeAndDo ->
          helper.waitForMessage 'aio:configured', assertMessage
          helper.publishSettings
            type: "aio:configure"
            dataType: "aio:configure:remove_env_variables",
            data: ['RDS_HOST', 'RDS_PASSWORD'],
            name: "mclovins-container-1"

  describe 'aio:destroy', ->
    beforeEach (done) ->
      childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container 1 mclovins-container 192.168.254.2 10000", timeout:5000, (err, stdout, stderr) ->
        return done(err) if err
        childProcess.exec "sudo #{scriptPath}/boxer-stop-container mclovins-container-1", timeout: 5000, (err, stdout, stderr) ->
          childProcess.exec "sudo #{scriptPath}/boxer-unmount-container 'mclovins-container-1'", timeout: 5000, (err, stdout, stderr) ->
            cleanDB ->
              publisher.hset 'aio:boxes', "mclovins-container-1", '{"id":1,"name":"mclovins-container","ip":"192.168.254.2","port":10000,"diskSpace":"1G","memory":"256M","containerTemplate":"test_container_template"}'
              helper.runBox done

    it 'should destroy the container and remove all remnants', (done) ->
      assertMessage = (message) ->
        expect(message.id).to.eql 'test.action.io'
        expect(message.boxId).to.eql 1

        expect(fs.existsSync("/var/lib/lxc/mclovins-container-1")).to.be.false
        expect(fs.existsSync("/var/lib/lxc/mclovins-container-1_delta")).to.be.false
        expect(fs.readFileSync("/etc/projid")).to.not.match /mclovins-container-1:1/
        expect(fs.readFileSync("/etc/projects")).to.not.match /1:\/var\/lib\/lxc\/mclovins-container-1_delta\/rootfs\/home\/action/

        getIps (err, stdout, stderr) ->
          expect(stdout).to.not.match /192\.168\.254\.254:22/

          assertStop 'mclovins-container-1', ->
            publisher.hget 'aio:boxes', 'mclovins-container-1', (err, res) ->
              expect(res).to.be.null
              done()

      helper.subscribeAndDo ->
        helper.waitForMessage 'aio:destroyed', assertMessage
        helper.publishSettings type: "aio:destroy", name: "mclovins-container-1"
