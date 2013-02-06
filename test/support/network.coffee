childProcess = require 'child_process'

module.exports =
  getIps: (cb) ->
    childProcess.exec "sudo iptables -L -t nat", timeout: 5000, cb
