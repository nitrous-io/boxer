module.exports = klass = class BaseMessage
  @type: ''

  constructor: (attributes) ->

  encode: ->
    JSON.stringify(this)
