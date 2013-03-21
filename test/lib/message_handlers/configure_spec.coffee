sinon = require 'sinon'
settings = require './../../../config/settings'
Boxer = require './../../../app/lib/boxer'
Box = require './../../../app/lib/box'
{ ConfigureMessage, InvalidParamsMessage } = require './../../../app/protocol'
{ configure } = require './../../../app/lib/message_handlers'

waitMessage = (cb) -> setTimeout cb, 10

describe 'Archive', ->
  boxer = message = null
  before ->
    boxer = new Boxer(settings)
    message = new ConfigureMessage(id: boxer.id, name: "box-name")
    boxer.publisher.publish = sinon.stub()

  context 'when the box does not exist in database', ->
    it 'returns an invalid message', (done) ->
      configure boxer, message
      waitMessage ->
        if message = JSON.parse boxer.publisher.publish.args[0][1]
          expect(message.type).to.eq InvalidParamsMessage.type
          done()
