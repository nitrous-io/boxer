Box = require '../../app/lib/box'
childProcess = require 'child_process'
scriptPath = __dirname.replace('test/lib', 'scripts/')

describe Box, ->
  box = cbSpy = null

  beforeEach ->
    box = new Box(1)
    box.name = 'rails-box'
    box.containerTemplate = 'ruby-container-template'
    box.lxcRoot = '/var/lib/lxc'
    box.memory = 256
    box.diskSpace = 4096

    cbSpy = sinon.spy()

  describe '#mountContainer', ->
    beforeEach ->
      sinon.stub box, '_execShellCommand', (cmd, args, opts, cb) ->
      box._mountContainer(cbSpy)

    it 'should call _execShellCommand with the right options', ->
      box._execShellCommand.should.have.been.calledWith("boxer-mount-container",
                                                        ['/var/lib/lxc', 'rails-box', 'ruby-container-template'],
                                                        sudo: true,
                                                        cbSpy)

  describe '#unmountContainer', ->
    beforeEach ->
      sinon.stub box, '_execShellCommand', (cmd, args, opts, cb) ->
      box._unmountContainer(cbSpy)

    it 'should call _execShellCommand with the right options', ->
      box._execShellCommand.should.have.been.calledWith("boxer-unmount-container",
                                                        ['/var/lib/lxc', 'rails-box'],
                                                        sudo: true,
                                                        cbSpy)
  describe '#configureBox', ->
    beforeEach ->
      box.ip = '192.168.254.254'
      sinon.stub box, '_execShellCommand', (cmd, args, opts, cb) ->
      box._configureBox(cbSpy)

    it 'should call _execShellCommand with the right options', ->
      box._execShellCommand.should.have.been.calledWith("boxer-configure-box",
                                                        ['/var/lib/lxc', 'rails-box', 'ruby-container-template', '192.168.254.254'],
                                                        sudo: true,
                                                        cbSpy)

  describe '#setUpPortForwarding', ->
    beforeEach ->
      box.ip = '192.168.254.254'
      box.port = 21000
      sinon.stub box, '_execShellCommand', (cmd, args, opts, cb) ->
      box._setUpPortForwarding(cbSpy)

    it 'should call _execShellCommand with the right options', ->
      box._execShellCommand.should.have.been.calledWith("boxer-setup-portforwarding",
                                                   ['192.168.254.254', 21000],
                                                   sudo: true,
                                                   cbSpy)

  describe '#releasePortForwarding', ->
    beforeEach ->
      box.ip = '192.168.254.254'
      box.port = 21000
      sinon.stub box, '_execShellCommand', (cmd, args, opts, cb) ->
      box._releasePortForwarding(cbSpy)

    it 'should call _execShellCommand with the right options', ->
      box._execShellCommand.should.have.been.calledWith("boxer-release-portforwarding",
                                                   ['192.168.254.254', 21000],
                                                   sudo: true,
                                                   cbSpy)

  describe '#startContainer', ->
    beforeEach ->
      box.ip = '192.168.254.254'
      sinon.stub box, '_execShellCommand', (cmd, args, opts, cb) ->
      box._startContainer(cbSpy)

    it 'should call _execShellCommand with the right options', ->
      box._execShellCommand.should.have.been.calledWith("boxer-start-container",
                                                        ['rails-box', '192.168.254.254'],
                                                        sudo: true,
                                                        cbSpy)

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

    context 'with a maligned prefix', ->
      beforeEach ->
        box._execShellCommand "foo",
                              ["hello"],
                              sudo: false,
                              prefix: "/usr/bin/",
                              cbSpy

      it 'should execute the command with the sanitized prefix', ->
        childProcess.exec.should.have.been.calledWith("/usr/bin/foo 'hello'", timeout: 0)
        cbSpy.should.have.been.called
