{ exec } = require 'child_process'
settings = require '../../config/settings'

module.exports = () ->
  args = Array.prototype.slice.call arguments
  done = args.pop()
  stratName = args.shift()
  scriptPath = __dirname + "/scripts"
  command = ["sudo", scriptPath + "/boxer-create-" + stratName].concat(args)
  commandStr = command.join(" ")
  console.log "Executing command: #{commandStr}"
  exec commandStr, timeout: 0, (err, stdout, stderr) -> done(err)
