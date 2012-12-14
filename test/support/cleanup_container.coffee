childProcess = require 'child_process'

module.exports = (done) ->
  scriptPath = __dirname.replace('test/support', 'scripts')
  command = "sudo #{scriptPath}/boxer-cleanup-tests"
  childProcess.exec command, timeout: 5000, (err, stdout, stderr) ->
    done(err)
