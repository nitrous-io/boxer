{ exec } = require 'child_process'
settings = require '../../config/settings'

module.exports = () ->
  args = Array.prototype.slice.call arguments
  done = args.pop()
  scriptPath = __dirname.replace('test/support', 'scripts')
  command = ["sudo", scriptPath + "/boxer-setup-test-container"].concat(args)
  command.push settings.selectedVG
  exec command.join(" "), timeout: 0, (err) -> done(err)
