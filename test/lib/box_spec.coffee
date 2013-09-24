Box                 = require '../../app/lib/box'
ResourcePool        = require '../../app/lib/resource_pool'
childProcess        = require 'child_process'
scriptPath          = __dirname.replace('test/lib', 'scripts/')
settings            = require '../../config/settings'
initRedisClientWith = require('../../app/lib/utils').initRedisClientWith

describe Box, ->
  box = cbSpy = null

  beforeEach ->
    box = new Box(1)
    box.name = 'rails-box'
    box.containerTemplate = 'ruby-container-template'
    box.memory = '256M'
    box.diskSpace = '1G'
    box.disk = '/lxc/disk1'
    cbSpy = sinon.spy()

  describe '#valid', ->
    box = null

    context 'onCreate is true', ->
      context 'valid box', ->
        it 'should be true', ->
          expect(box.valid(onCreate: true)).to.be.true

      context 'invalid box', ->
        beforeEach ->
          box.name = null

        it 'should be false', ->
          expect(box.valid(onCreate: true)).to.be.false

    context 'onCreate is false', ->
      context 'valid box', ->
        it 'should be true', ->
          expect(box.valid()).to.be.true

      context 'invalid box', ->
        beforeEach ->
          box.name = null

        it 'should be false', ->
          expect(box.valid()).to.be.false

  describe '#containerName', ->
    it 'includes box id and name', ->
      expect(box.containerName()).to.equal("rails-box-1")

  describe '#memoryUnit', ->
    it 'returns the unit of memory included in the box', ->
      box.memory = '256M'
      expect(box.memoryUnit()).to.equal('M')
      box.memory = '1G'
      expect(box.memoryUnit()).to.equal('G')
      box.memory = '1024'
      expect(box.memoryUnit()).to.equal('')

  describe '#totalMemory', ->
    it 'includes swap size of the box', ->
      box.memory = '256M'
      expect(box.totalMemory()).to.equal('512M')
      box.memory = '1G'
      expect(box.totalMemory()).to.equal('2G')
      box.memory = '1024'
      expect(box.totalMemory()).to.equal('2048')

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

  describe 'when an error occurrs within _execShellCommand', ->
    beforeEach (done) ->
      notifyStub = sinon.stub().callsArg(1)

      sinon.stub box, '_cleanupDeltaContainer', (cb) ->
        done()

      sinon.stub box, '_mountContainer', (cb) -> box._execShellCommand '../support/fail-script', [], sudo: true, cb

      sinon.stub box, '_currentState', ->
        { name: 'someState',   onAdvance: '_mountContainer', onRollback: '_cleanupDeltaContainer' }

      box._advance()

    afterEach ->
      box.airbreakClient = null
      box._currentState.restore()
      box._cleanupDeltaContainer.restore()
      box._mountContainer.restore()

    it 'should invoke the rollback', () ->
      box._cleanupDeltaContainer.should.have.been.called
