childProcess = require 'child_process'

lxcInfo = (boxName, cb) ->
  childProcess.exec "sudo lxc-info -n #{boxName}", timeout: 5000, cb

module.exports =
  assertStop: (boxName, cb) ->
    lxcInfo boxName, (err, stdout, stderr) ->
      expect(stdout).to.match /STOPPED/
      cb()

  assertRunning: (boxName, cb) ->
    lxcInfo boxName, (err, stdout, stderr) ->
      expect(stdout).to.match /RUNNING/
      cb()
