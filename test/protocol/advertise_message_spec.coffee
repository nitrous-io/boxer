AdvertiseMessage = require '../../app/protocol/advertise_message'

describe 'AdvertiseMessage', ->
  describe 'constructor', ->
    beforeEach ->
      @msg = new AdvertiseMessage(id:'id', freeMemory: 8192, type: 'aio:advertise', runtimes: ['ruby', 'php'], returnVars: {'abc':'def','xyz':123})

    it 'should instantiate all of its properties', ->
      @msg.id.should.eql 'id'
      @msg.type.should.eql 'aio:advertise'
      @msg.freeMemory.should.eql 8192
      @msg.runtimes.should.eql ['ruby', 'php']
      # returnVars is set in the base class BaseMessage
      @msg.returnVars.should.eql {'abc':'def','xyz':123}

  describe '.construct', ->
    beforeEach ->
      @msg = AdvertiseMessage.construct()

    it 'should construct an AdvertiseMessage object, with all the attributes filled in', ->
      @msg.id.should.not.be.empty
      @msg.freeMemory.should.be.above 0
      @msg.type.should.eql 'aio:advertise'
