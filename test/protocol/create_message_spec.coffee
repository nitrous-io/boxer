CreateMessage = require '../..//app/protocol/create_message'

describe 'CreateMessage', ->
  it 'converts boxId and cpuShares to numeric values', ->
    msg = new CreateMessage(boxId: "1234", cpuShares: "1024")
    expect(msg.boxId).to.eql 1234
    expect(msg.cpuShares).to.eql 1024
