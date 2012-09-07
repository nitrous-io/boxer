AutoAdvancingStateMachine = require '../../app/lib/auto_advancing_state_machine'

class TestStateMachine extends AutoAdvancingStateMachine
  states: [
    { name: 'A', onAdvance: 'goToB', onRollback: null }
    { name: 'B', onAdvance: 'goToC', onRollback: 'goBackToA' }
    { name: 'C', onAdvance: null,    onRollback: null }
  ]

describe 'StateMachine', ->
  sm = null

  beforeEach ->
    sm = new TestStateMachine
    sm.goToB     = sinon.stub()
    sm.goToC     = sinon.stub()
    sm.goBackToA = sinon.stub()

  it 'sets initial state', ->
    sm.state.should.eql 'A'

  describe 'state', ->
    describe 'getter', ->
      it "returns current state's name", ->
        sm._currentStateIndex = 1
        sm.state.should.eql 'B'
        sm._currentStateIndex = 2
        sm.state.should.eql 'C'

    describe 'setter', ->
      it 'sets current state by name', ->
        sm.state = 'B'
        sm._currentStateIndex.should.eql 1
        sm.state = 'C'
        sm._currentStateIndex.should.eql 2

  describe '#start', ->
    context 'when nothing fails', ->
      beforeEach ->
        sm.goToB.callsArgOn(0, sm)
        sm.goToC.callsArgOn(0, sm)
        sm.start()

      it 'advances all the way to C', ->
        sm.goToB.called.should.be.true
        sm.goToC.called.should.be.true
        sm.state.should.eql 'C'

    context 'when goToB fails', ->
      beforeEach ->
        sm.goToB.callsArgOnWith(0, sm, new Error('error'))
        sm.start()

      it 'stays at A', ->
        sm.goToB.called.should.be.true
        sm.state.should.eql 'A'

    context 'when goToC fails', ->
      beforeEach ->
        sm.goToB.callsArgOn(0, sm)
        sm.goToC.callsArgOnWith(0, sm, new Error('error'))
        sm.goBackToA.callsArgOn(0, sm)
        sm.start()

      it 'goes all the way back to A', ->
        sm.goToB.called.should.be.true
        sm.goToC.called.should.be.true
        sm.goBackToA.called.should.be.true
        sm.state.should.eql 'A'

