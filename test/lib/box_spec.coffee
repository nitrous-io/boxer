Box                 = require '../../app/lib/box'
ResourcePool        = require '../../app/lib/resource_pool'
childProcess        = require 'child_process'
scriptPath          = __dirname.replace('test/lib', 'scripts/')
initRedisClientWith = require('../../app/lib/utils').initRedisClientWith

describe Box, ->
  box = cbSpy = null

  beforeEach ->
    box = new Box(1)
    box.name = 'rails-box'
    box.containerTemplate = 'ruby-container-template'
    box.memory = 256
    box.diskSpace = 4096

    cbSpy = sinon.spy()

  describe '#valid', ->
    box = null

    context 'onCreate is true', ->
      context 'valid box', ->
        beforeEach ->
          box = new Box(1)
          box.name = 'mclovin'
          box.containerTemplate = 'ruby'
          box.memory = 256
          box.diskSpace = 4096

        it 'should be true', ->
          expect(box.valid(onCreate: true)).to.be.true

      context 'invalid box', ->
        beforeEach ->
          box = new Box(1)
          box.name = 'mclovin'

        it 'should be false', ->
          expect(box.valid(onCreate: true)).to.be.false

    context 'onCreate is false', ->
      context 'valid box', ->
        beforeEach ->
          box = new Box(1)
          box.name = 'mclovin'

        it 'should be true', ->
          expect(box.valid()).to.be.true

      context 'invalid box', ->
        beforeEach ->
          box = new Box()

        it 'should be false', ->
          expect(box.valid()).to.be.false

  describe '#mountContainer', ->
    beforeEach ->
      sinon.stub box, '_execShellCommand', (cmd, args, opts, cb) ->
      box._mountContainer(cbSpy)

    it 'should call _execShellCommand with the right options', ->
      box._execShellCommand.should.have.been.calledWith("boxer-mount-container",
                                                        [1, "rails-box", "ruby-container-template", 4096],
                                                        sudo: true,
                                                        cbSpy)

  describe '#unmountContainer', ->
    beforeEach ->
      sinon.stub box, '_execShellCommand', (cmd, args, opts, cb) ->
      box._unmountContainer(cbSpy)

    it 'should call _execShellCommand with the right options', ->
      box._execShellCommand.should.have.been.calledWith("boxer-unmount-container",
                                                        ['rails-box'],
                                                        sudo: true,
                                                        cbSpy)

  describe '#setupDeltaContainer', ->
    beforeEach ->
      sinon.stub box, '_execShellCommand', (cmd, args, opts, cb) ->
      box._setupDeltaContainer(cbSpy)

    it 'should call _execShellCommand with the right options', ->
      box._execShellCommand.should.have.been.calledWith("boxer-setup-delta-container",
                                                        [1, "rails-box", "ruby-container-template"],
                                                        sudo: true,
                                                        cbSpy)

  describe '#cleanupDeltaContainer', ->
    beforeEach ->
      sinon.stub box, '_execShellCommand', (cmd, args, opts, cb) ->
      box._cleanupDeltaContainer(cbSpy)

    it 'should call _execShellCommand with the right options', ->
      box._execShellCommand.should.have.been.calledWith("boxer-cleanup-delta-container",
                                                        ['rails-box'],
                                                        sudo: true,
                                                        cbSpy)

  describe '#configureBox', ->
    beforeEach ->
      box.ip = '192.168.254.2'
      box.gateway = '192.168.254.1'
      box.interface = 'br-lxc-254'
      sinon.stub box, '_execShellCommand', (cmd, args, opts, cb) ->
      box._configureBox(cbSpy)

    it 'should call _execShellCommand with the right options', ->
      box._execShellCommand.should.have.been.calledWith("boxer-configure-box",
                                                        ['rails-box', 'ruby-container-template', '192.168.254.2', '192.168.254.1', 'br-lxc-254', 15001, 15001],
                                                        sudo: true,
                                                        cbSpy)

  describe '#setUpPortForwarding', ->
    beforeEach ->
      box.ip = '192.168.254.2'
      box.port = 21000
      sinon.stub box, '_execShellCommand', (cmd, args, opts, cb) ->
      box._setUpPortForwarding(cbSpy)

    it 'should call _execShellCommand with the right options', ->
      box._execShellCommand.should.have.been.calledWith("boxer-setup-portforwarding",
                                                   ['192.168.254.2', 21000],
                                                   sudo: true,
                                                   cbSpy)

  describe '#releasePortForwarding', ->
    beforeEach ->
      box.ip = '192.168.254.2'
      box.port = 21000
      sinon.stub box, '_execShellCommand', (cmd, args, opts, cb) ->
      box._releasePortForwarding(cbSpy)

    it 'should call _execShellCommand with the right options', ->
      box._execShellCommand.should.have.been.calledWith("boxer-release-portforwarding",
                                                   ['192.168.254.2', 21000],
                                                   sudo: true,
                                                   cbSpy)

  describe '#_releaseResources', ->
    error = null

    beforeEach ->
      box.ip = '192.168.254.2'
      box.gateway = '192.168.254.1'
      box.interface = 'br-lxc-254'
      box.port = 21000
      error = new Error 'some error'
      sinon.stub ResourcePool, 'release', (resources, cb) -> cb(error)
      box._releaseResources(cbSpy)

    afterEach ->
      ResourcePool.release.restore()

    it "calls ResourcePool.release with the box's ip and port", ->
      resources = ResourcePool.release.args[0][0]
      expect(resources).to.deep.equal
        ip: box.ip
        gateway: box.gateway
        interface: box.interface
        port: box.port
      expect(cbSpy).to.have.been.calledWith error

  describe "#removeDefaultKeyPair", ->
    beforeEach ->
      sinon.stub box, '_execShellCommand', (cmd, args, opts, cb) ->

    it 'removes default public and private key for the box', ->
      box._removeDefaultKeyPair(cbSpy)
      box._execShellCommand.should.have.been.calledWith(
        "boxer-remove-default-key-pair",
        ['rails-box'],
        sudo: true,
        cbSpy
      )

  describe '#startContainer', ->
    beforeEach ->
      box.ip = '192.168.254.2'
      sinon.stub box, '_execShellCommand', (cmd, args, opts, cb) ->
      box._startContainer(cbSpy)

    it 'should call _execShellCommand with the right options', ->
      box._execShellCommand.should.have.been.calledWith("boxer-start-container",
                                                        ['rails-box', '192.168.254.2'],
                                                        sudo: true,
                                                        cbSpy)

  describe '.startAll', ->
    beforeEach (done) ->
      childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container 1 mclovins-container-1 192.168.254.2 10000 dont-start", timeout:5000, (err, stdout, stderr) ->
        done(err) if err
        childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container 2 mclovins-container-2 192.168.254.3 10001 dont-start", timeout:5000, (err, stdout, stderr) ->
          done(err) if err
          childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container 3 mclovins-container-3 192.168.254.4 10002 dont-start", timeout:5000, (err, stdout, stderr) ->
            done(err) if err
            cleanDB ->
              settings = require('../../config/settings')
              redisStoreSettings = settings.redisStore
              redis = initRedisClientWith(redisStoreSettings)
              redis.hset 'aio:boxes', "mclovins-container-1", '{"id":1,"name":"mclovins-container-1","ip":"192.168.254.2","port":10000,"diskSpace":"1G","memory":"256M","containerTemplate":"test_container_template","containerState":"running"}', ->
                redis.hset 'aio:boxes', "mclovins-container-2", '{"id":2,"name":"mclovins-container-2","ip":"192.168.254.3","port":10001,"diskSpace":"1G","memory":"256M","containerTemplate":"test_container_template","containerState":"stopped"}', ->
                  redis.hset 'aio:boxes', "mclovins-container-3", '{"id":3,"name":"mclovins-container-3","ip":"192.168.254.4","port":10002,"diskSpace":"1G","memory":"256M","containerTemplate":"test_container_template","containerState":"running"}', ->
                    Box.startAll done

    afterEach (done) ->
      cleanupContainer 'mclovins-container-1', ->
        cleanupContainer 'mclovins-container-2', ->
          cleanupContainer 'mclovins-container-3', ->
            done()

    it 'should start all boxes which have its containerState set to running', (done) ->
      childProcess.exec "sudo lxc-info -n mclovins-container-1", timeout: 5000, (err, stdout, stderr) ->
        expect(stdout).to.match /RUNNING/

        childProcess.exec "sudo lxc-info -n mclovins-container-2", timeout: 5000, (err, stdout, stderr) ->
          expect(stdout).to.match /STOPPED/

          childProcess.exec "sudo lxc-info -n mclovins-container-3", timeout: 5000, (err, stdout, stderr) ->
            expect(stdout).to.match /RUNNING/
            done()


  describe '#stopContainer', ->
    beforeEach ->
      sinon.stub box, '_execShellCommand', (cmd, args, opts, cb) ->
      box._stopContainer(cbSpy)

    it 'should call _execShellCommand with the right options', ->
      box._execShellCommand.should.have.been.calledWith("boxer-stop-container",
                                                        ['rails-box']
                                                        sudo: true,
                                                        cbSpy)

  describe '#_execShellCommand', ->
    beforeEach ->
      sinon.stub childProcess, 'exec', (cmd, opts, cb) ->
        cb(null, "success", null)

    afterEach ->
      childProcess.exec.restore()

    context 'with sudo', ->
      beforeEach ->
        box._execShellCommand "foo",
                              ["hello", "world"],
                              sudo: true,
                              cbSpy

      it 'should execute the command with the sudo prefixed', ->
        childProcess.exec.should.have.been.calledWith("sudo #{scriptPath}foo 'hello' 'world'", timeout: 0)
        cbSpy.should.have.been.called

    context 'without sudo', ->
      beforeEach ->
        box._execShellCommand "foo",
                              ["hello"],
                              sudo: false,
                              cbSpy

      it 'should execute the command without the sudo prefixed', ->
        childProcess.exec.should.have.been.calledWith("#{scriptPath}foo 'hello'", timeout: 0)
        cbSpy.should.have.been.called

    context 'without option', ->
      beforeEach ->
        box._execShellCommand "foo", ["hello"], cbSpy

      it 'should execute the command without the sudo prefixed', ->
        childProcess.exec.should.have.been.calledWith("#{scriptPath}foo 'hello'", timeout: 0)
        cbSpy.should.have.been.called

    context 'without args', ->
      beforeEach ->
        box._execShellCommand "foo", cbSpy

      it 'should execute the command without the sudo prefixed', ->
        childProcess.exec.should.have.been.calledWith("#{scriptPath}foo", timeout: 0)
        cbSpy.should.have.been.called
