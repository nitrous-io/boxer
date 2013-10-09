env = process.env.NODE_ENV

runtimes =
  development:
    runtimes: {}
  test:
    runtimes:
      test: 'test_container_template'
    disks: ['/lxc/disk1']
    selectedDisk: '/lxc/disk1'
    mountMethod: "lvm"
    selectedVG: "boxhost"

  production:
    runtimes: {}

module.exports = runtimes[env]
