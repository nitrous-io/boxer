MessageParser = require '../../app/lib/message_parser'
LocateMessage = require '../../app/protocol/locate_message'
AdvertiseMessage = require '../../app/protocol/advertise_message'
CreateMessage = require '../../app/protocol/create_message'

describe 'MessageParser', ->
  describe '.decode', ->
    context 'empty type string', ->
      it "should throw an error", ->
        expect(MessageParser.decode('{"abc":"def"}')).to.be.null

    context 'type does not exist', ->
      it "should throw an error", ->
        expect(MessageParser.decode('{"type":"junk_type"}')).to.be.null

    context 'type is aio.locate', ->
      it 'should return a LocateMessage object', ->
        msg = MessageParser.decode('{"type":"aio.locate"}')
        msg.should.be.an.instanceOf(LocateMessage)

    context 'type is aio.advertise', ->
      it 'should return an AdvertiseMessage object', ->
        msg = MessageParser.decode('{"type":"aio.advertise"}')
        msg.should.be.an.instanceOf(AdvertiseMessage)

    context 'type is aio.create', ->
      it 'should return a CreateMessage object', ->
        msg = MessageParser.decode('{"type":"aio.create"}')
        msg.should.be.an.instanceOf(CreateMessage)
