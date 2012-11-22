env = process.env.NODE_ENV

runtimes =
  development:
    runtimes: {}
  test:
    runtimes:
      test: 'test_container_template'
  production:
    runtimes: {}

module.exports = runtimes[env]
