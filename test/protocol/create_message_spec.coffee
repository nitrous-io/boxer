CreateMessage = require '../..//app/protocol/create_message'

describe 'CreateMessage', ->
  it 'converts boxId and cpuShares to numeric values', ->
    msg = new CreateMessage(boxId: "1234", cpuShares: "1024")
    expect(msg.boxId).to.eql 1234
    expect(msg.cpuShares).to.eql 1024

  it 'converts premium to boolean value', ->
    msg = new CreateMessage(premium: "true")
    expect(msg.premium).to.eql true
    msg = new CreateMessage(premium: "false")
    expect(msg.premium).to.eql false

    msg = new CreateMessage(premium: true)
    expect(msg.premium).to.eql true
    msg = new CreateMessage(premium: false)
    expect(msg.premium).to.eql false
