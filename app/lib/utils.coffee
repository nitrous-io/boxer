module.exports =
  escapeShellArg: (string) ->
    if typeof string == 'number'
      return "'#{string.toString()}'"
    if typeof string == 'string'
      return "'" + string.replace(/'/g, "'\"'\"'") + "'" 
    null
