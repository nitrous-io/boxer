childProcess = require 'child_process'

module.exports = (done) ->
  scriptPath = __dirname.replace('test/support', 'scripts')
  childProcess.exec "sudo #{scriptPath}/boxer-cleanup-tests", timeout: 5000, (err, stdout, stderr) ->
    done(err)
