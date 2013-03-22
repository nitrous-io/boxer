childProcess = require 'child_process'
settings = require '../../config/settings'

module.exports = (name, ip, done) ->
  scriptPath = __dirname.replace('test/support', 'scripts')
  command = "sudo #{scriptPath}/boxer-cleanup-tests #{name} #{ip} #{settings.selectedDisk}"
  childProcess.exec command, timeout: 0, (err, stdout, stderr) ->
    done(err)
