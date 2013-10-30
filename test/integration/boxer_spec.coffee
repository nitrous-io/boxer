Boxer               = require '../../app/lib/boxer'
Box                 = require '../../app/lib/box'
MessageParser       = require '../../app/lib/message_parser'
initRedisClientWith = require('../../app/lib/utils').initRedisClientWith
childProcess        = require 'child_process'
fs                  = require 'fs'
_                   = require 'underscore'
async               = require 'async'
scriptPath          = __dirname.replace('test/integration', 'scripts')
settings            = require('../../config/settings')
redisMQSettings     = settings.redisMQ
redisStoreSettings  = settings.redisStore
http                = require 'http'

describe 'Boxer', ->
  boxer = coach = publisher = null

  ip = '192.168.254.2'

  resource =
    gateway:'192.168.254.1',
    interface:'br-lxc-254',
    port:'10000'

  # for each strategy, we are going to run a full suite of test to make sure
  # that everything works. For each of the strategy, we requires a cleanup
  # script with name boxer-create-#{stratName} and
  # boxer-clean-#{stratName} in test/support/scripts
  strategies =
    xfs: { disk: '/lxc/disk1', mount: 'aufs', quotaMethod: 'prjquota' }
    ext4: { disk: '/lxc/disk2', mount: 'aufs', quotaMethod: 'usrquota' }
    lvm: { disk: '/lxc/disk1', mount: 'lvm', quotaMethod: 'prjquota', selectedVG: 'aio_boxhost' }

  publishSettings = (attributes) ->
    attributes.id ?= 'test.action.io'
    attributes.name ?= 'mclovins-container'
    publisher.publish settings.boxerChannel, JSON.stringify(attributes)

  # Helper to create a new box
  createBox = (attributes={}) ->
    attributes.type ?= 'aio:create'
    attributes.boxId ?= 1
    attributes.runtime ?= "test"
    attributes.memory ?= "256M"
    attributes.diskSpace ?= '2000M'
    attributes.cpuShares ?= '2048'
    attributes.mount ?= "lvm"
    attributes.quotaMethod ?= "projquota"
    attributes.selectedVG ?= settings.selectedVG

    attributes.publicKeys ?= []
    attributes.snapshotURL ?= null
    publishSettings attributes

  # start a box with selected settings
  runBox = (andDone) ->
    boxer = new Boxer(settings)
    boxer.run andDone

  # wait for a specific message type from coach, when we get it, pass the
  # message to callback
  waitForMessage = (messageType, callback, done) ->
    coach.on 'message', (channel, rawMessage) ->
      message = MessageParser.decode(rawMessage)
      if message.type == messageType
        callback(message, done)

  subscribeAndDo = (callback) ->
    coach.subscribe settings.coachChannel, (err, result) ->
      throw err if err
      callback()

  testSuite = (stratValue, stratName, finished) -> describe "strategy: #{ stratName }", ->
    beforeEach (done) ->
      @timeout(10000)
      settings = require('../../config/settings')
      redisMQSettings = settings.redisMQ
      redisStoreSettings = settings.redisStore
      publisher = initRedisClientWith(redisMQSettings)
      coach = initRedisClientWith(redisMQSettings)
      cleanupContainer stratName, 'mclovins-container-1', stratValue.disk, '15001', stratValue.selectedVG, done
      settings.mountMethod = stratValue.mount
      settings.selectedDisk = stratValue.disk
      settings.quotaMethod = stratValue.quotaMethod
      settings.selectedVG = stratValue.selectedVG

    afterEach (done) ->
      boxer.cleanup() if boxer
      coach.unsubscribe() if coach
      publisher.unsubscribe() if publisher
      boxer = coach = publisher = null
      cleanupContainer stratName, 'mclovins-container-1', stratValue.disk, '15001', stratValue.selectedVG, ->
	done()
	finished()

    describe 'aio:create', ->
      beforeEach (done) ->
        cleanDB ->
          multi = publisher.multi()
          multi.rpush 'aio:available_resources', ip
          multi.hmset "aio:nwr:#{ip}", resource
          multi.exec (err, replies) ->
            return done(err) if err
            runBox done

      it 'returns aio:created with the requisite properties when successfully provisioned', (done) ->
        assertMessage = (message) ->
          # check true container root in selected disk instead of /var/lib/lxc
          containerRoot = "/var/lib/lxc/mclovins-container-1"
          root = "#{containerRoot}/rootfs"
          lxcConfigFile = "#{containerRoot}/config"

          networkConfig = fs.readFileSync("#{root}/etc/network/interfaces")
          name = fs.readFileSync("#{root}/etc/hostname")
          hostsfile = fs.readFileSync("#{root}/etc/hosts")
          publicKeys = fs.readFileSync("#{root}/etc/ssh/univ_public_keys").toString().trim().split("\n")

          # check message data
          expect(message.port).to.eql 10000
          expect(message.boxId).to.eql 1
          expect(message.id).to.eql 'test.action.io'
          expect(message.success).to.be.true
          expect(networkConfig).to.match /address 192.168.254.2/
          expect(name).to.match /mclovins-container-1/
          expect(hostsfile).to.match /mclovins-container-1/
          expect(publicKeys).to.eql ['public-key-1', 'public-key-2']

          # check that home content
          expect(fs.existsSync("/#{root}/home/action/.ssh")).to.be.true
          expect(fs.existsSync("/#{root}/home/action/workspace")).to.be.true
          expect(fs.existsSync("/#{root}/home/action/.ssh/id_rsa.pub")).to.be.true
          expect(fs.existsSync("/#{root}/home/action/.ssh/id_rsa")).to.be.true
          expect(fs.readFileSync("/#{root}/etc/passwd")).to.match /action:x:15001:15001/

          # check lxc config
          lxcConfigFileContent = fs.readFileSync(lxcConfigFile).toString()

          expect(lxcConfigFileContent).to.match /lxc.network.hwaddr = 02:00/
          expect(lxcConfigFileContent).to.match /lxc.cgroup.memory.limit_in_bytes = 256M/
          expect(lxcConfigFileContent).to.match /lxc.cgroup.memory.memsw.limit_in_bytes = 512M/
          expect(lxcConfigFileContent).to.match /lxc.cgroup.memory.swappiness = 60/
          expect(lxcConfigFileContent).to.match /lxc.cgroup.cpu.shares = 2048/

          # check /etc settings
          etcActionBoxId = fs.readFileSync("#{root}/etc/action/box_id").toString().trim()
          expect(etcActionBoxId).to.eql '1'
          etcActionBoxUser = fs.readFileSync("#{root}/etc/action/box_user").toString().trim()
          expect(etcActionBoxUser).to.eql 'action'

          # check uid and gid
          stats = fs.statSync("/#{root}/home/action")
          expect(stats.uid).to.eql 15001
          expect(stats.gid).to.eql 15001
          expect(fs.statSync("/#{root}/home/action/workspace").uid).to.eql 15001
          expect(fs.statSync("/#{root}/home/action/workspace").gid).to.eql 15001

          # check ip of the created container
          childProcess.exec "sudo iptables -L -t nat", (err, stdout, stderr) ->
            expect(stdout).to.match /192\.168\.254\.2:22/

            # check redis settings
            publisher.hget 'aio:boxes', 'mclovins-container-1', (err, res) ->
              msg = JSON.parse(res)
              expect(msg.id).to.eql 1
              expect(msg.name).to.eql 'mclovins-container'
              expect(msg.ip).to.eql '192.168.254.2'
              expect(msg.port).to.eql 10000
              expect(msg.memory).to.eql '256M'
              expect(msg.diskSpace).to.eql '2000M'
              expect(msg.boxerId).to.eql 'test.action.io'
              expect(msg.containerState).to.eql 'stopped'
	      expect(msg.disk).to.eql stratValue.disk
	      expect(msg.mount).to.eql stratValue.mount
	      expect(msg.quotaMethod).to.eql stratValue.quotaMethod
              expect(msg.selectedVG).to.eql settings.selectedVG
              done(err)

        subscribeAndDo ->
          waitForMessage 'aio:created', assertMessage
	  createBox _.extend(stratValue, { publicKeys: ["public-key-1", "public-key-2"] })

      context 'unsuccessful provisioning', ->
        assertCreateFailedMessage = (message, done) ->
          containerRoot = "/var/lib/lxc/mclovins-container-1"
          containerRootDelta = "/var/lib/lxc/mclovins-container-1_delta"

          expect(fs.existsSync(containerRoot)).to.be.false
          expect(fs.existsSync(containerRootDelta)).to.be.false
          expect(message.id).to.eql 'test.action.io'
          expect(message.success).to.eql false

          childProcess.exec "sudo iptables -L -t nat", (err, stdout, stderr) ->
            expect(stdout).to.not.match /192\.168\.254\.2:22/

            childProcess.exec "sudo lxc-info -n mclovins-container-1", (err, stdout, stderr) ->
              expect(stdout).to.match /STOPPED/

              publisher.hget 'aio:boxes', 'mclovins-container-1', (err, res) ->
                expect(res).to.be.null
                done(err)

        context 'no resources available on redis', ->
          beforeEach (andDone) -> cleanDB andDone

          it 'should return an aio:created message (with the success flag set to false) and not create the container', (done) ->
            subscribeAndDo ->
              waitForMessage 'aio:created', assertCreateFailedMessage, done
	      createBox stratValue

        context 'prepareContainer fails', ->
          beforeEach ->
            sinon.stub Box.prototype, '_prepareContainer', (cb) ->
              Box.prototype._execShellCommand '../test/support/mock-scripts/boxer-create-volume',
                ['mclovins-container-1', '1G', settings.selectedVG], sudo: true, cb

          afterEach ->
            Box.prototype._prepareContainer.restore()

          it 'should return an aio:created message (with the success flag set to false) and not create the container', (done) ->
            subscribeAndDo ->
              waitForMessage 'aio:created', assertCreateFailedMessage, done
	      createBox stratValue

        context 'mountContainer fails', ->
          beforeEach ->
            sinon.stub Box.prototype, '_mountContainer', (cb) ->
              Box.prototype._execShellCommand '../test/support/mock-scripts/boxer-mount-container',
                ['1', 'mclovins-container-1', settings.selectedVG], sudo: true, cb

          afterEach ->
            Box.prototype._mountContainer.restore()

          it 'should return an aio:created message (with the success flag set to false) and not create the container', (done) ->
            subscribeAndDo ->
              waitForMessage 'aio:created', assertCreateFailedMessage, done
	      createBox stratValue

        context 'configureBox fails', ->
          beforeEach ->
            sinon.stub Box.prototype, '_configureBox', (cb) ->
              Box.prototype._execShellCommand '../test/support/mock-scripts/boxer-configure-box',
                [1, 'mclovins-container-1', 'test_container_template', '512', '256M', '512M', '60', '192.168.254.2', '192.168.254.1', 'br-lxc-254', 15001, 15001],
                sudo: true, cb

          afterEach ->
            Box.prototype._configureBox.restore()

          it 'should return an aio:created message (with the success flag set to false) and not create the container', (done) ->
            subscribeAndDo ->
              waitForMessage 'aio:created', assertCreateFailedMessage, done
	      createBox stratValue

        context 'setupPortForwarding fails', ->
          beforeEach ->
            sinon.stub Box.prototype, '_setUpPortForwarding', (cb) ->
              Box.prototype._execShellCommand '../test/support/mock-scripts/boxer-setup-portforwarding 192.168.254.2 10000', [], sudo: true, cb

          afterEach ->
            Box.prototype._setUpPortForwarding.restore()

          it 'should return an aio:created message (with the success flag set to false) and not create the container', (done) ->
            subscribeAndDo ->
              waitForMessage 'aio:created', assertCreateFailedMessage, done
	      createBox stratValue

        context 'setDefaultKeyPair fails', ->
          beforeEach ->
            sinon.stub Box.prototype, '_setDefaultKeyPair', (cb) ->
              Box.prototype._execShellCommand '../support/fail-script', [], sudo: true, cb

          afterEach ->
            Box.prototype._setDefaultKeyPair.restore()

          it 'should return an aio:created message (with the success flag set to false) and not create the container', (done) ->
            subscribeAndDo ->
              waitForMessage 'aio:created', assertCreateFailedMessage, done
	      createBox stratValue

        context 'save fails', ->
          beforeEach ->
            sinon.stub Box.prototype, 'save', -> throw new Error("OMG")

          afterEach ->
            Box.prototype.save.restore()

          it 'should return an aio:created message with the success flag set to false', (done) ->
            subscribeAndDo ->
              waitForMessage 'aio:created', assertCreateFailedMessage, done
	      createBox stratValue

      context 'invalid params', ->
        it 'should return an aio:created message (with the success flag set to false) and not create the container', (done) ->
          assertMessage = (message) ->
            expect(message.id).to.eql 'test.action.io'
            expect(message.success).to.eql false

            childProcess.exec "sudo iptables -L -t nat", (err, stdout, stderr) ->
              expect(stdout).to.not.match /192\.168\.254\.2:22/

              childProcess.exec "sudo lxc-info -n mclovins-container-1", (err, stdout, stderr) ->
                expect(stdout).to.match /STOPPED/

                publisher.hget 'aio:boxes', 'mclovins-container-1', (err, res) ->
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

    describe 'aio:restart' , ->
      beforeEach (done) ->
	createContainer stratName, "1", "mclovins-container", "192.168.254.2", "10000", stratValue.disk, "15001", (err) ->
          return done(err) if err
          cleanDB ->
	    boxJSON = _.extend stratValue, {
              id: 1
              name: "mclovins-container"
              ip: "192.168.254.2"
              port: 10000
              diskSpace: "2000M"
              memory: "256M"
              containerTemplate: "test_container_template"
	      containerState: "running"
	    }
	    publisher.hset 'aio:boxes', "mclovins-container-1", JSON.stringify(boxJSON)
            runBox done

      it 'should restart an already created container', (done) ->
        assertMessage = (message) ->
          expect(message.id).to.eql 'test.action.io'
          expect(message.boxId).to.eql 1

          childProcess.exec "sudo lxc-info -n mclovins-container-1", (err, stdout, stderr) ->
            expect(stdout).to.match /RUNNING/

            publisher.hget 'aio:boxes', 'mclovins-container-1', (err, res) ->
              msg = JSON.parse(res)
              expect(msg.id).to.eql 1
              expect(msg.name).to.eql 'mclovins-container'
              expect(msg.containerState).to.eql 'running'
              done(err)

        subscribeAndDo ->
          waitForMessage 'aio:restarted', assertMessage
          publishSettings type: "aio:restart", name: "mclovins-container-1"

    describe 'aio:stop', ->
      beforeEach (done) ->
	createContainer stratName, "1", "mclovins-container", "192.168.254.2", "10000", stratValue.disk, "15001", (err) ->
          return done(err) if err
          cleanDB ->
	    boxJSON = _.extend stratValue, {
              id: 1
              name: "mclovins-container"
              ip: "192.168.254.2"
              port: 10000
              diskSpace: "2000M"
              memory: "256M"
              containerTemplate: "test_container_template"
	      containerState: "running"
	    }
	    publisher.hset 'aio:boxes', "mclovins-container-1", JSON.stringify(boxJSON)
            runBox done

      it 'should return an aio:stopped message with the box\'s id present', (done) ->
        assertMessage = (message) ->
          expect(message.id).to.eql 'test.action.io'
          expect(message.boxId).to.eql 1
          expect(fs.existsSync("/var/lib/lxc/mclovins-container-1/rootfs")).to.be.false

          childProcess.exec "sudo lxc-info -n mclovins-container-1", (err, stdout, stderr) ->
            expect(stdout).to.match /STOPPED/
            publisher.hget 'aio:boxes', 'mclovins-container-1', (err, res) ->
              msg = JSON.parse(res)
              expect(msg.id).to.eql 1
              expect(msg.name).to.eql 'mclovins-container'
              expect(msg.containerState).to.eql 'stopped'
              done(err)

        subscribeAndDo ->
          waitForMessage 'aio:stopped', assertMessage
          publishSettings type: "aio:stop", name: "mclovins-container-1"

    describe 'aio:start' , ->
      beforeEach (done) ->
	createContainer stratName, "1", "mclovins-container", "192.168.254.2", "10000", stratValue.disk, "15001", "dont-start", (err) ->
          done(err) if err
          cleanDB ->
	    boxJSON = _.extend stratValue, {
              id: 1
              name: "mclovins-container"
              ip: "192.168.254.2"
              port: 10000
              diskSpace: "2000M"
              memory: "256M"
              containerTemplate: "test_container_template"
	      containerState: "stopped"
	    }
	    publisher.hset 'aio:boxes', "mclovins-container-1", JSON.stringify(boxJSON)
            runBox done

      it 'should start an already created container', (done) ->
        assertMessage = (message) ->
          expect(message.id).to.eql 'test.action.io'
          expect(message.boxId).to.eql 1

          childProcess.exec "sudo lxc-info -n mclovins-container-1", (err, stdout, stderr) ->
            expect(stdout).to.match /RUNNING/
            publisher.hget 'aio:boxes', 'mclovins-container-1', (err, res) ->
              msg = JSON.parse(res)
              expect(msg.id).to.eql 1
              expect(msg.name).to.eql 'mclovins-container'
              expect(msg.containerState).to.eql 'running'
              done(err)

        subscribeAndDo ->
          waitForMessage 'aio:started', assertMessage
          publishSettings type: "aio:start", name: "mclovins-container-1"

    describe 'aio:info_request', ->
      beforeEach (done) ->
	createContainer stratName, "1", "mclovins-container", "192.168.254.2", "10000", stratValue.disk, "15001", (err) ->
	  return done(err) if err
          cleanDB ->
	    boxJSON = _.extend stratValue, {
              id: 1
              name: "mclovins-container"
              ip: "192.168.254.2"
              port: 10000
              diskSpace: "2000M"
              memory: "256M"
              containerTemplate: "test_container_template"
              containerState: "running"
	    }
	    publisher.hset 'aio:boxes', "mclovins-container-1", JSON.stringify(boxJSON)
            runBox done

      it 'returns usage stats of the box', (done) ->
        assertMessage = (message) ->
          expect(message.info.storageUsage).to.match /([0-9]+\.*)?/
          expect(message.info.memoryUsage).to.match /([0-9]+\.*)?/
          expect(message.info.lxcStatus).to.eql "RUNNING"
          done()

        subscribeAndDo ->
          waitForMessage 'aio:info_response', assertMessage
          publishSettings type: "aio:info_request", name: "mclovins-container-1"

    describe 'aio:configure', ->
      publicKeysFile = null
      publicKey = null

      beforeEach (done) ->
        publicKeysFile = "/var/lib/lxc/mclovins-container-1/rootfs/etc/ssh/univ_public_keys"
	createContainer stratName, "1", "mclovins-container", "192.168.254.2", "10000", stratValue.disk, "15001", (err) ->
	  return done(err) if err
          cleanDB ->
	    boxJSON = _.extend stratValue, {
              id: 1
              name: "mclovins-container"
              ip: "192.168.254.2"
              port: 10000
              diskSpace: "2000M"
              memory: "256M"
              containerTemplate: "test_container_template"
              containerState: "running"
	    }
	    publisher.hset 'aio:boxes', "mclovins-container-1", JSON.stringify(boxJSON)
            runBox done

      context 'adding public keys', ->
        beforeEach ->
          publicKey = "ssh-rsa AAAAB3NzaC1yc2== arun@iPhone"

        it 'should add a public key to the box', (done) ->
          assertMessage = (message) ->
            expect(message.id).to.eql 'test.action.io'
            expect(message.boxId).to.eql 1
            expect(fs.existsSync(publicKeysFile)).to.be.true
            expect(fs.readFileSync(publicKeysFile).toString().trim()).to.eql publicKey
            done()

          subscribeAndDo ->
            waitForMessage 'aio:configured', assertMessage
            publishSettings type: "aio:configure", dataType: "aio:configure:add_public_key", data: publicKey, name: "mclovins-container-1"

      context 'removing public keys', ->
        publicKey1 = publicKey2 = null

        beforeEach (done) ->
          publicKey1 = "ssh-rsa AAAAB3NzaC1y== arun@iPhone"
          publicKey2 = "ssh-rsa AAAAB3NzaC1y== arun@iPhone.local"

          childProcess.exec "sudo scripts/boxer-add-public-keys 'mclovins-container-1' '#{publicKey1}'", (err) ->
            if err
              throw err
            else
              childProcess.exec "sudo scripts/boxer-add-public-keys 'mclovins-container-1' '#{publicKey2}'", (err) ->
                if err then throw err else done()

        it 'should remove the public key from the box', (done) ->
          assertMessage = (message) ->
            expect(message.id).to.eql 'test.action.io'
            expect(message.boxId).to.eql 1

            publicKeysFile = "/var/lib/lxc/mclovins-container-1/rootfs/etc/ssh/univ_public_keys"
            expect(fs.existsSync(publicKeysFile)).to.be.true
            expect(fs.readFileSync(publicKeysFile).toString().trim()).to.eql publicKey2
            done()

          subscribeAndDo ->
            waitForMessage 'aio:configured', assertMessage
            publishSettings type: "aio:configure", dataType: "aio:configure:remove_public_key", data: publicKey1, name: "mclovins-container-1"

      context 'setting env variables', ->
        it 'sets the variables to /etc/profile', (done) ->
          assertMessage = (message) ->
            environmentFile = "/var/lib/lxc/mclovins-container-1/rootfs/etc/environment"
            env = fs.readFileSync(environmentFile).toString()
            expect(env).to.contain 'RDS_HOST=mysql://insecure'
            expect(env).to.contain 'RDS_PASSWORD=mysql-insecure'
            done()

          subscribeAndDo ->
            waitForMessage 'aio:configured', assertMessage
            publishSettings
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

          subscribeAndDo ->
            waitForMessage 'aio:configured', assertMessage
            publishSettings
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
          childProcess.exec "sudo scripts/boxer-set-env-variables 'mclovins-container-1' 'RDS_HOST=123'", (err, stdout, stderr) ->
            if err then throw err else done()

        it 'remove the variables from /etc/profile', (done) ->
          assertMessage = (message) ->
            environmentFile = "/var/lib/lxc/mclovins-container-1/rootfs/etc/environment"
            env = fs.readFileSync(environmentFile).toString()
            expect(env).to.not.contain 'RDS_HOST=123'
            done()

          subscribeAndDo ->
            waitForMessage 'aio:configured', assertMessage
            publishSettings
              type: "aio:configure"
              dataType: "aio:configure:remove_env_variables",
              data: ['RDS_HOST', 'RDS_PASSWORD'],
              name: "mclovins-container-1"

      context 'change auth username and password', ->
        before ->
          sinon.stub http, 'get', (opts, cb) ->
              cb()

        after ->
          http.get.restore()

        it 'changes the values stored in redis', (done) ->
          assertMessage = (message) ->
            publisher.hget 'aio:boxes', 'mclovins-container-1', (err, res) ->
              msg = JSON.parse(res)
              expect(msg.id).to.eql 1
              expect(msg.authUsername).to.eql 'admin'
              expect(msg.authPassword).to.eql 'password'
              done(err)

          subscribeAndDo ->
            waitForMessage 'aio:configured', assertMessage
            publishSettings
              type: "aio:configure"
              dataType: "aio:configure:update_auth",
              name: "mclovins-container-1"
              data: {
                "auth_username": "admin",
                "auth_password": "password"
              }

        it 'pings Cartman to invalidate cache', (done) ->
          assertMessage = (message) ->
            options =
              hostname: settings.cartmanHost
              port: settings.cartmanPort
              path: "/invalidate_cache?id=mclovins-container-1"
            expect(http.get).to.have.been.calledWith options, sinon.match.func
            done()

          subscribeAndDo ->
            waitForMessage 'aio:configured', assertMessage
            publishSettings
              type: "aio:configure"
              dataType: "aio:configure:update_auth",
              name: "mclovins-container-1"
              data: {
                "auth_username": "admin",
                "auth_password": "password"
              }

      context 'upgrading box specs', ->
        context 'unsuccessful upgrade (disk space used is more than the new limit)', ->
          before ->
            sinon.stub Box.prototype, 'quota', (cb) ->
              cb null, used: (512 * 1024), limit: (1024 * 1024 * 1024)

          after ->
            Box.prototype.quota.restore()

          it 'returns a aio:configured message with success set to false', (done) ->
            assertMessage = (message) ->
              # message set to false
              expect(message.success).to.be.false

              # check lxc config
              lxcConfigFile = "/var/lib/lxc/mclovins-container-1/config"
              lxcConfigFileContents = fs.readFileSync(lxcConfigFile).toString()
              expect(lxcConfigFileContents).to.match /lxc.cgroup.memory.limit_in_bytes = 256M/
              expect(lxcConfigFileContents).to.match /lxc.cgroup.memory.memsw.limit_in_bytes = 512M/

              # check current quota limit
	      reportContainerLimit stratName, "mclovins-container-1", "15001", stratValue.disk, (err, stdout, stderr) ->
                # The Disk Space Quota stays the same
		switch stratName
		  when "xfs"
		    expect(stdout).to.match /.*?-(2|2.0)G/
		  when "lvm"
		    expect(stdout).to.match /.*?-(1.9|2.0)G/
		  when "ext4"
		    # FIXME: not sure why the usrquota returns 2049M here
		    expect(stdout).to.match /.*?-(2048|2049)M/

                # check redis settings
                publisher.hget 'aio:boxes', 'mclovins-container-1', (err, res) ->
                  msg = JSON.parse(res)
                  expect(msg.memory).to.eql '256M'
                  expect(msg.diskSpace).to.eql '2000M'
                  expect(msg.containerState).to.eql 'running'
                  done()

            subscribeAndDo ->
              waitForMessage 'aio:configured', assertMessage
              publishSettings
                type: "aio:configure"
                dataType: "aio:configure:change_specs"
                data:
                  memory: "256M"
                  diskSpace: "0.2G"
                name: "mclovins-container-1"

        context 'successful upgrade', ->
          it "upgrades the box's memory and disk space limit", (done) ->
            assertMessage = (message) ->
              # message set to true
              expect(message.success).to.be.true

              # check lxc config
              lxcConfigFile = "/var/lib/lxc/mclovins-container-1/config"
              expect(fs.readFileSync(lxcConfigFile).toString()).to.match /lxc.cgroup.memory.limit_in_bytes = 512M/
              expect(fs.readFileSync(lxcConfigFile).toString()).to.match /lxc.cgroup.memory.memsw.limit_in_bytes = 1024M/
              expect(fs.readFileSync(lxcConfigFile).toString()).to.match /lxc.cgroup.cpu.shares = 2048/

              # check current quota limit
	      reportContainerLimit stratName, "mclovins-container-1", "15001", stratValue.disk, (err, stdout, stderr) ->
                # df doesnt report exact volume. lv/ext4 probably eats some
		switch stratName
		  when "xfs"
		    expect(stdout.trim()).to.match /.*?-(3|3.0)G/
		  when "lvm"
		    expect(stdout.trim()).to.match /.*?-(2.9|3.0)G/
		  when "ext4"
		    expect(stdout.trim()).to.match /.*?-3072M/

                # check redis settings
                publisher.hget 'aio:boxes', 'mclovins-container-1', (err, res) ->

                  msg = JSON.parse(res)
                  expect(msg.memory).to.eql '512M'
                  expect(msg.diskSpace).to.eql '3072M'
                  expect(msg.cpuShares).to.eql '2048'
                  expect(msg.containerState).to.eql 'running'
                  done()

            subscribeAndDo ->
              waitForMessage 'aio:configured', assertMessage
              publishSettings
                type: "aio:configure"
                dataType: "aio:configure:change_specs"
                data:
                  memory: "512M"
                  diskSpace: "3G"
                  cpuShares: "2048"
                name: "mclovins-container-1"

          it "accepts float gigabyte unit for disk space", (done) ->
            assertMessage = (message) ->
              # message set to true
              expect(message.success).to.be.true

              # check current quota limit
	      reportContainerLimit stratName, "mclovins-container-1", "15001", stratValue.disk, (err, stdout, stderr) ->
		switch stratName
		  when "xfs"
		    expect(stdout).to.match /.*?-1\.5G/
		  when "lvm"
		    expect(stdout).to.match /.*?-(1.4|1.5)G/
		  when "ext4"
		    expect(stdout).to.match /.*?-1536M/

                # check redis settings
                publisher.hget 'aio:boxes', 'mclovins-container-1', (err, res) ->
                  msg = JSON.parse(res)
                  expect(msg.diskSpace).to.eql '1536M'
                  done()

            subscribeAndDo ->
              waitForMessage 'aio:configured', assertMessage
              publishSettings
                type: "aio:configure"
                dataType: "aio:configure:change_specs"
                data:
                  diskSpace: "1.5G"
                name: "mclovins-container-1"

          it "accepts megabyte unit for disk space", (done) ->
            assertMessage = (message) ->
              # message set to true
              expect(message.success).to.be.true

              # check current quota limit
	      reportContainerLimit stratName, "mclovins-container-1", "15001", stratValue.disk, (err, stdout, stderr) ->
		switch stratName
		  when "xfs"
		    expect(stdout).to.match /.*?-(2|2.0)G/
		  when "lvm"
		    expect(stdout).to.match /.*?-(1.9|2.0)G/
		  when "ext4"
		    expect(stdout).to.match /.*?-2048M/
                # check redis settings
                publisher.hget 'aio:boxes', 'mclovins-container-1', (err, res) ->
                  msg = JSON.parse(res)
                  expect(msg.diskSpace).to.eql '2048M'
                  done()

            subscribeAndDo ->
              waitForMessage 'aio:configured', assertMessage
              publishSettings
                type: "aio:configure"
                dataType: "aio:configure:change_specs"
                data:
                  diskSpace: "2048M"
                name: "mclovins-container-1"

    describe 'aio:destroy', ->
      beforeEach (done) ->
	createContainer stratName, "1", "mclovins-container", "192.168.254.2", "10000", stratValue.disk, "15001", (err) ->
          return done(err) if err
          childProcess.exec "sudo #{scriptPath}/boxer-stop-container mclovins-container-1", (err, stdout, stderr) ->
	    cleanDB ->
	      boxJSON = _.extend stratValue, {
		id: 1
		name: "mclovins-container"
		ip: "192.168.254.2"
		port: 10000
		diskSpace: "1G"
		memory: "256M"
		containerTemplate: "test_container_template"
		containerState: "stopped"
	      }
	      publisher.hset 'aio:boxes', "mclovins-container-1", JSON.stringify(boxJSON)
	      runBox done

      it 'should destroy the container and remove all remnants', (done) ->
        assertMessage = (message) ->
          expect(message.id).to.eql 'test.action.io'
          expect(message.boxId).to.eql 1

          expect(fs.existsSync("/var/lib/lxc/mclovins-container-1")).to.be.false
          expect(fs.existsSync("/var/lib/lxc/mclovins-container-1_delta")).to.be.false
	  switch stratName
	    when "lvm"
	      expect(fs.existsSync("/dev/#{settings.selectedVG}/mclovins-container-1")).to.be.false
	    when "ext4", "xfs"
	      expect(fs.existsSync("/#{stratValue.disk}/mclovins-container-1")).to.be.false

          childProcess.exec "sudo iptables -L -t nat", (err, stdout, stderr) ->
            expect(stdout).to.not.match /192\.168\.254\.254:22/

            childProcess.exec "sudo lxc-info -n mclovins-container-1", (err, stdout, stderr) ->
              expect(stdout).to.match /STOPPED/

              publisher.hget 'aio:boxes', 'mclovins-container-1', (err, res) ->
                expect(res).to.be.null
                done()

        subscribeAndDo ->
          waitForMessage 'aio:destroyed', assertMessage
          publishSettings type: "aio:destroy", name: "mclovins-container-1"

  # start running tests sequentially here
  tests = _.map strategies, (stratValue, stratName) -> (cb) -> testSuite(stratValue, stratName, cb)
  async.series tests, (err) -> console.log(err) if err
