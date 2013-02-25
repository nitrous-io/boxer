childProcess = require 'child_process'

module.exports = (name, ip, done) ->
  scriptPath = __dirname.replace('test/support', 'scripts')
  command = "sudo #{scriptPath}/boxer-cleanup-tests #{name} #{ip}"
  childProcess.exec command, timeout: 0, (err, stdout, stderr) ->
    done(err)
