LocateMessage = require '../..//app/protocol/locate_message'

describe 'LocateMessage', ->
  describe 'constructor', ->
    beforeEach ->
      @msg = new LocateMessage(type: 'aio:locate')

    it 'should instantiate the type instance var', ->
      @msg.type.should.eql 'aio:locate'
