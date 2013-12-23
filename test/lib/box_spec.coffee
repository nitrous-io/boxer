Box                 = require '../../app/lib/box'
ResourcePool        = require '../../app/lib/resource_pool'
childProcess        = require 'child_process'
os                  = require 'os'
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

  it 'makes sure that its numeric attributes are numeric', ->
    box.id = "1"
    box.port = "1234"
    box.swappines = "60"
    box.cpuShares = "512"
    box.premium = "true"
    res = JSON.parse(box.encode())
    expect(res["id"]).to.eql 1
    expect(res["port"]).to.eql 1234
    expect(res["swappiness"]).to.eql 60
    expect(res["cpuShares"]).to.eql 512
    expect(res["premium"]).to.eql true

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

  describe '#getQuotaMethod', ->
    it 'returns usrquota if box.quotaMethod is set to usrquota', ->
      box.quotaMethod = "usrquota"
      expect(box.getQuotaMethod()).to.eql "usrquota"

    it 'returns prjquota otherwise', ->
      box.quotaMethod = "projquota"
      expect(box.getQuotaMethod()).to.eql "prjquota"
      box.quotaMethod = null
      expect(box.getQuotaMethod()).to.eql "prjquota"

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
    it 'defaults to twice the memory', ->
      box.memory = '256M'
      expect(box.totalMemory()).to.equal('512M')
      box.memory = '1G'
      expect(box.totalMemory()).to.equal('2G')
      box.memory = '1024'
      expect(box.totalMemory()).to.equal('2048')

    it 'returns the total memory in MB including the virtual memory specified', ->
      box.memory = '256M'
      box.virtualMemory = '512M'
      expect(box.totalMemory()).to.equal('768M')
      box.memory = '1024M'
      box.virtualMemory = '131072' # 128M
      expect(box.totalMemory()).to.equal('1152M')

  describe '#_cpuSet', ->
    context 'when there is only 1 CPU on the host', ->
      beforeEach ->
        sinon.stub(os, 'cpus').returns(['core 0'])

      afterEach ->
        os.cpus.restore()

      it 'returns 0', ->
        expect(box._cpuSet()).to.equal('0')

    context 'when there are 2 CPUs on the host', ->
      beforeEach ->
        sinon.stub(os, 'cpus').returns(['core 0', 'core 1'])

      afterEach ->
        os.cpus.restore()

      it 'returns 1', ->
        expect(box._cpuSet()).to.equal('1')

    context 'when there are more than 2 CPUs on the host', ->
      beforeEach ->
        sinon.stub(os, 'cpus').returns(['core 0', 'core 1', 'core 2', 'core 3'])

      afterEach ->
        os.cpus.restore()

      it 'returns a range of CPUs from 1 up to the (total number of CPU - 1) on the host', ->
        expect(box._cpuSet()).to.equal('1,2,3')

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
