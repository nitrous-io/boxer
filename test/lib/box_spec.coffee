Box          = require '../../app/lib/box'
ResourcePool = require '../../app/lib/resource_pool'

describe Box, ->
  box = cbSpy = null

  beforeEach ->
    box = new Box(1)
    box.name = 'rails-box'
    box.containerTemplate = 'ruby-container-template'
    box.memory = '256M'
    box.diskSpace = '1G'

    cbSpy = sinon.spy()

  describe '#valid', ->
    box = null

    context 'onCreate is true', ->
      context 'valid box', ->
        beforeEach ->
          box = new Box(1)
          box.name = 'mclovin'
          box.containerTemplate = 'ruby'
          box.memory = '256M'
          box.diskSpace = '1G'

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
      expect(box.totalMemory()).to.equal('768M')
      box.memory = '1G'
      expect(box.totalMemory()).to.equal('3G')
      box.memory = '1024'
      expect(box.totalMemory()).to.equal('3072')

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
