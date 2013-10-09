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

  describe '#mountMethod', ->
    it 'returns lvm if box.mount is set to lvm', ->
      box.mount = "lvm"
      expect(box.mountMethod()).to.eql "lvm"

    it 'returns aufs if box.mount is aufs', ->
      box.mount = "aufs"
      expect(box.mountMethod()).to.eql "aufs"

    it 'returns overlayfs if box.mount is overlayfs', ->
      box.mount = "overlayfs"
      expect(box.mountMethod()).to.eql "overlayfs"

    it 'returns aufs if box.aufs is true', ->
      box.aufs = true
      expect(box.mountMethod()).to.eql "aufs"

    it 'returns overlayfs if box does not have aufs', ->
      expect(box.mountMethod()).to.eql "overlayfs"

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
