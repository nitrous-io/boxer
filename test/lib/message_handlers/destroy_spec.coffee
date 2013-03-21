sinon = require 'sinon'
settings = require './../../../config/settings'
Boxer = require './../../../app/lib/boxer'
Box = require './../../../app/lib/box'
{ DestroyMessage, InvalidParamsMessage } = require './../../../app/protocol'
{ destroy } = require './../../../app/lib/message_handlers'

waitMessage = (cb) -> setTimeout cb, 10

describe 'Destroy', ->
  boxer = message = null
  before ->
    boxer = new Boxer(settings)
    message = new DestroyMessage(id: boxer.id, name: "box-name")
    boxer.publisher.publish = sinon.stub()

  context 'when the box does not exist in database', ->
    it 'returns an invalid message', (done) ->
      destroy boxer, message
      waitMessage ->
        if message = JSON.parse boxer.publisher.publish.args[0][1]
          expect(message.type).to.eq InvalidParamsMessage.type
          done()
