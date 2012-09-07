_ = require 'underscore'

module.exports = klass = class AutoAdvancingStateMachine
  states: []

  constructor: ->
    @_currentStateIndex = 0

  _currentState: ->
    @states[@_currentStateIndex]

  _currentStateName: ->
    this._currentState().name

  _setCurrentStateByName: (name) ->
    for state, i in @states
      if state.name == name
        @_currentStateIndex = i
        return

  _advanceDone: (err) ->
    if err
      this._rollback()
    else
      if (@_currentStateIndex += 1) < (@states.length - 1)
        this._advance()

  _advance: ->
    state = this._currentState()
    this[state.onAdvance]?(@_advanceDone)

  _rollbackDone: ->
    if (@_currentStateIndex -= 1) > 0
      this._rollback()

  _rollback: ->
    state = this._currentState()
    this[state.onRollback]?(@_rollbackDone)

  start: ->
    this._advance()

klass::__defineGetter__ 'state', ->
  this._currentStateName()

klass::__defineSetter__ 'state', (name) ->
  this._setCurrentStateByName(name)

