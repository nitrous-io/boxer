env = process.env.NODE_ENV

runtimes =
  development:
    runtimes: {}
  test:
    runtimes:
      test: 'test-container-template'
  production:
    runtimes: {}

module.exports = runtimes[env]
