childProcess = require 'child_process'

module.exports = (name, done) ->
  scriptPath = __dirname.replace('test/support', 'scripts')
  command = "sudo #{scriptPath}/boxer-cleanup-tests #{name}"
  childProcess.exec command, timeout: 5000, (err, stdout, stderr) ->
    done(err)
