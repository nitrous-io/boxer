Box = require '../../app/lib/box'
childProcess = require 'child_process'
scriptPath = __dirname.replace('test/lib', 'scripts/')

describe Box, ->
  box = cbSpy = null

  beforeEach ->
    box = new Box('rails-box', 'ruby-container-template', '/var/lib/lxc', 256, 4096, [], null)
    cbSpy = sinon.spy()

  describe '#mountVolume', ->
    beforeEach ->
      sinon.stub box, '_execShellCommand', (cmd, args, opts, cb) ->
      box.mountVolume(cbSpy)

    it 'should call _execShellCommand with the right options', ->
      expect(box._execShellCommand).was.calledWith("boxer-mount-volume",
                                                   ['/var/lib/lxc', 'rails-box', 'ruby-container-template'],
                                                   sudo: true,
                                                   cbSpy)

  describe '#configureBox', ->
    beforeEach ->
      box.ip = '192.168.254.254'
      sinon.stub box, '_execShellCommand', (cmd, args, opts, cb) ->
      box.configureBox(cbSpy)

    it 'should call _execShellCommand with the right options', ->
      expect(box._execShellCommand).was.calledWith("boxer-configure-box",
                                                   ['/var/lib/lxc', 'rails-box', '192.168.254.254'],
                                                   sudo: true,
                                                   cbSpy)

  describe '#setUpPortForwarding', ->
    beforeEach ->
      box.ip = '192.168.254.254'
      box.port = 21000
      sinon.stub box, '_execShellCommand', (cmd, args, opts, cb) ->
      box.setUpPortForwarding(cbSpy)

    it 'should call _execShellCommand with the right options', ->
      expect(box._execShellCommand).was.calledWith("boxer-setup-portforwarding",
                                                   ['192.168.254.254', 21000],
                                                   sudo: true,
                                                   cbSpy)

  describe '#setUpWebProxy', ->
    beforeEach ->
      box.ip = '192.168.254.254'
      sinon.stub box, '_execShellCommand', (cmd, args, opts, cb) ->
      box.setUpWebProxy(cbSpy)

    it 'should call _execShellCommand with the right options', ->
      expect(box._execShellCommand).was.calledWith("boxer-setup-webproxy",
                                                   ['rails-box', 'rails_box', '192.168.254.254'],
                                                   sudo: true,
                                                   cbSpy)
  describe '#notifySuccess', ->
    beforeEach ->
      sinon.stub box, '_execShellCommand', (cmd, args, opts, cb) ->
      box.notifySuccess(cbSpy)

    it 'should call _execShellCommand with the right options', ->
      expect(box._execShellCommand).was.calledWith("boxer-notify-success",
                                                   ['rails-box'],
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
        expect(childProcess.exec).was.calledWith("sudo #{scriptPath}foo 'hello' 'world'", timeout: 2000)
        expect(cbSpy).was.called()

    context 'without sudo', ->
      beforeEach ->
        box._execShellCommand "foo",
                              ["hello"],
                              sudo: false,
                              cbSpy

      it 'should execute the command without the sudo prefixed', ->
        expect(childProcess.exec).was.calledWith("#{scriptPath}foo 'hello'", timeout: 2000)
        expect(cbSpy).was.called()

    context 'without option', ->
      beforeEach ->
        box._execShellCommand "foo", ["hello"], cbSpy

      it 'should execute the command without the sudo prefixed', ->
        expect(childProcess.exec).was.calledWith("#{scriptPath}foo 'hello'", timeout: 2000)
        expect(cbSpy).was.called()

    context 'without args', ->
      beforeEach ->
        box._execShellCommand "foo", cbSpy

      it 'should execute the command without the sudo prefixed', ->
        expect(childProcess.exec).was.calledWith("#{scriptPath}foo", timeout: 2000)
        expect(cbSpy).was.called()

    context 'with a maligned prefix', ->
      beforeEach ->
        box._execShellCommand "foo",
                              ["hello"],
                              sudo: false,
                              prefix: "/usr/bin/",
                              cbSpy

      it 'should execute the command with the sanitized prefix', ->
        expect(childProcess.exec).was.calledWith("/usr/bin/foo 'hello'", timeout: 2000)
        expect(cbSpy).was.called()
