AdvertiseMessage = require '../../app/protocol/advertise_message'

describe 'AdvertiseMessage', ->
  describe 'constructor', ->
    beforeEach ->
      @msg = new AdvertiseMessage(id:'id', freeMemory: 8192, type: 'aio.advertise', runtimes: ['ruby', 'php'])

    it 'should instantiate all of its properties', ->
      @msg.id.should.eql 'id'
      @msg.type.should.eql 'aio.advertise'
      @msg.freeMemory.should.eql 8192
      @msg.runtimes.should.eql ['ruby', 'php']


  describe '.construct', ->
    beforeEach ->
      @msg = AdvertiseMessage.construct()

    it 'should construct an AdvertiseMessage object, with all the attributes filled in', ->
      @msg.id.should.not.be.empty
      @msg.freeMemory.should.be.above 0
      @msg.runtimes.should.eql ['test']
      @msg.type.should.eql 'aio.advertise'
