MessageParser = require '../../app/lib/message_parser'
LocateMessage = require '../../app/protocol/locate_message'
AdvertiseMessage = require '../../app/protocol/advertise_message'
StartMessage = require '../../app/protocol/start_message'

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

    context 'type is aio.start', ->
      it 'should return a StartMessage object', ->
        msg = MessageParser.decode('{"type":"aio.start"}')
        msg.should.be.an.instanceOf(StartMessage)
