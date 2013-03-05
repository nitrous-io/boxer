childProcess = require 'child_process'
utils = require '../../app/lib/utils'
scriptPath = __dirname.replace('test/lib', 'scripts/')

describe 'utils', ->
  cbSpy = null

  describe '#execShellCommand', ->
    beforeEach ->
      cbSpy = sinon.spy()
      sinon.stub childProcess, 'exec', (cmd, opts, cb) -> cb(null, "success", null)

    afterEach ->
      childProcess.exec.restore()

    context 'with sudo', ->
      beforeEach ->
        utils.execShellCommand "foo", ["hello", "world"], sudo: true, cbSpy

      it 'should execute the command with the sudo prefixed', ->
        childProcess.exec.should.have.been.calledWith("sudo #{scriptPath}foo 'hello' 'world'", timeout: 0)
        cbSpy.should.have.been.called

    context 'without sudo', ->
      beforeEach ->
        utils.execShellCommand "foo", ["hello"], sudo: false, cbSpy

      it 'should execute the command without the sudo prefixed', ->
        childProcess.exec.should.have.been.calledWith("#{scriptPath}foo 'hello'", timeout: 0)
        cbSpy.should.have.been.called

    context 'without option', ->
      beforeEach ->
        utils.execShellCommand "foo", ["hello"], cbSpy

      it 'should execute the command without the sudo prefixed', ->
        childProcess.exec.should.have.been.calledWith("#{scriptPath}foo 'hello'", timeout: 0)
        cbSpy.should.have.been.called

    context 'without args', ->
      beforeEach ->
        utils.execShellCommand "foo", cbSpy

      it 'should execute the command without the sudo prefixed', ->
        childProcess.exec.should.have.been.calledWith("#{scriptPath}foo", timeout: 0)
        cbSpy.should.have.been.called
