{ exec } = require 'child_process'

module.exports = (stratName, containerName, uid, disk, cb) ->
  scriptPath = __dirname.replace('test/support', 'scripts')
  if stratName == "xfs"
    script = scriptPath + "/boxer-report-current-limit"
    args = [disk, containerName]
  else if stratName == "ext4"
    script = scriptPath + "/usrquota/boxer-report-current-limit"
    args = [disk, uid]
  else
    script = scriptPath + "/lvm/boxer-report-current-limit"
    args = [containerName]

  command = ["sudo", script].concat(args)
  commandStr = command.join(" ")
  console.log "Executing: #{commandStr}"
  exec commandStr, timeout: 0, cb
