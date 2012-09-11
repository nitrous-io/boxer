module.exports = klass = class BaseMessage
  @type: ''

  constructor: (attributes) ->
    @type = this.constructor.type

  encode: ->
    JSON.stringify(this)
