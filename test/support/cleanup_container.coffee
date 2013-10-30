childProcess = require 'child_process'
settings = require '../../config/settings'

module.exports = () ->
  args = Array.prototype.slice.call arguments
  done = args.pop()
  stratName = args.shift()
  scriptPath = __dirname + "/scripts"
  command = ["sudo", scriptPath + "/boxer-clean-" + stratName].concat args
  commandStr = command.join(" ")
  console.log "Executing command: #{commandStr}"
  childProcess.exec commandStr, timeout: 0, (err) -> done(err)
