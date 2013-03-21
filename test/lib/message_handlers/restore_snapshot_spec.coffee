sinon = require 'sinon'
settings = require './../../../config/settings'
Boxer = require './../../../app/lib/boxer'
Box = require './../../../app/lib/box'
{ RestoreSnapshotMessage, InvalidParamsMessage } = require './../../../app/protocol'
{ restoreSnapshot } = require './../../../app/lib/message_handlers'

waitMessage = (cb) -> setTimeout cb, 10

describe 'RestoreSnapshot', ->
  boxer = message = null
  before ->
    boxer = new Boxer(settings)
    message = new RestoreSnapshotMessage(id: boxer.id, name: "box-name", snapshotUrl: "s3://hello")
    boxer.publisher = { publish: sinon.stub() }

  context 'when the box does not exist in database', ->
    it 'returns an invalid message', (done) ->
      restoreSnapshot boxer, message
      waitMessage ->
        if message = JSON.parse boxer.publisher.publish.args[0][1]
          expect(message.type).to.eq InvalidParamsMessage.type
          done()
