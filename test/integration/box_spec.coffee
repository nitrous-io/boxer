Box                 = require '../../app/lib/box'
ResourcePool        = require '../../app/lib/resource_pool'
childProcess        = require 'child_process'
scriptPath          = __dirname.replace('test/integration', 'scripts')
initRedisClientWith = require('../../app/lib/utils').initRedisClientWith
async               = require 'async'
_                   = require 'underscore'



describe Box, ->
  describe ".find", ->
    it 'returns callback with error when we cant find the box', (done) ->
      callback = (err, box) =>
        expect(err).to.be.an.instanceof(Error)
        done()
      Box.find 'non-existent-box', callback

  # for each strategy, we are going to run a full suite of test to make sure
  # that everything works. For each of the strategy, we requires a cleanup
  # script with name boxer-create-#{stratName} and
  # boxer-clean-#{stratName} in test/support/scripts
  strategies =
    xfs: { disk: '/lxc/disk1', mount: 'aufs', quotaMethod: 'prjquota' }
    ext4: { disk: '/lxc/disk2', mount: 'aufs', quotaMethod: 'usrquota' }
    lvm: { disk: '/lxc/disk1', mount: 'lvm', quotaMethod: 'prjquota', selectedVG: 'aio_boxhost' }

  testSuite = (stratValue, stratName, finished) -> describe "strategy: #{ stratName }", ->
    after -> finished()

    describe '.startAll', ->
      beforeEach (done) ->
	async.series [
	  (cb) -> cleanupContainer stratName, 'mclovins-container-1-1', stratValue.disk, '15001', stratValue.selectedVG, -> cb()
	  (cb) -> cleanupContainer stratName, 'mclovins-container-2-2', stratValue.disk, '15002', stratValue.selectedVG, -> cb()
	  (cb) -> cleanupContainer stratName, 'mclovins-container-3-3', stratValue.disk, '15003', stratValue.selectedVG, -> cb()
	  (cb) -> createContainer stratName, "1", "mclovins-container-1", "192.168.254.2", "10000", stratValue.disk, "15001", "dont-start", cb
	  (cb) -> createContainer stratName, "2", "mclovins-container-2", "192.168.254.3", "10001", stratValue.disk, "15002", "dont-start", cb
	  (cb) -> createContainer stratName, "3", "mclovins-container-3", "192.168.254.4", "10002", stratValue.disk, "15003", "dont-start", cb
	], (err) ->
          return done(err) if err
          cleanDB ->
            settings = require('../../config/settings')
            redisStoreSettings = settings.redisStore
            redis = initRedisClientWith(redisStoreSettings)
	    commonJson = _.extend stratValue, {
              diskSpace: "1G"
              memory: "256M"
              containerTemplate: "test_container_template"
	      containerState: "running"
	    }
	    container1 = JSON.stringify(_.extend(commonJson, {id: "1", name: "mclovins-container-1", ip: "192.168.254.2", port: 10000, containerState: "running"}))
	    container2 = JSON.stringify(_.extend(commonJson, {id: "2", name: "mclovins-container-2", ip: "192.168.254.3", port: 10001, containerState: "stopped"}))
	    container3 = JSON.stringify(_.extend(commonJson, {id: "3", name: "mclovins-container-3", ip: "192.168.254.4", port: 10002, containerState: "running"}))
	    redis.hset 'aio:boxes', "mclovins-container-1-1", container1, ->
	      redis.hset 'aio:boxes', "mclovins-container-2-2", container2, ->
		redis.hset 'aio:boxes', "mclovins-container-3-3", container3, ->
		  Box.startAll done

      afterEach (done) ->
	async.series [
	  (cb) -> cleanupContainer stratName, 'mclovins-container-1-1', stratValue.disk, '15001', stratValue.selectedVG, -> cb()
	  (cb) -> cleanupContainer stratName, 'mclovins-container-2-2', stratValue.disk, '15002', stratValue.selectedVG, -> cb()
	  (cb) -> cleanupContainer stratName, 'mclovins-container-3-3', stratValue.disk, '15003', stratValue.selectedVG, -> cb()
	], done

      it 'should start all boxes which have its containerState set to running', (done) ->
	childProcess.exec "sudo lxc-info -n mclovins-container-1-1", (err, stdout, stderr) ->
	  expect(stdout).to.match /RUNNING/

	  childProcess.exec "sudo lxc-info -n mclovins-container-2-2", (err, stdout, stderr) ->
	    expect(stdout).to.match /STOPPED/

	    childProcess.exec "sudo lxc-info -n mclovins-container-3-3", (err, stdout, stderr) ->
	      expect(stdout).to.match /RUNNING/
	      done()

    describe '#quota', ->
      box = null

      beforeEach (done) ->
	cleanupContainer stratName, 'mclovins-container-1', stratValue.disk, '15001', stratValue.selectedVG, ->
	  createContainer stratName, "1", "mclovins-container", "192.168.254.2", "10000", stratValue.disk, "15001", "dont-start", (err) ->
	    return done(err) if err
	    cleanDB ->
	      settings = require('../../config/settings')
	      redisStoreSettings = settings.redisStore
	      redis = initRedisClientWith(redisStoreSettings)
	      boxJSON = _.extend stratValue, {
		id: 1
		name: "mclovins-container"
		ip: "192.168.254.2"
		port: 10000
		diskSpace: "1G"
		memory: "256M"
		containerTemplate: "test_container_template"
		containerState: "stopped"
	      }
	      redis.hset 'aio:boxes', "mclovins-container-1", JSON.stringify(boxJSON), ->
		Box.find "mclovins-container-1", (err, b) ->
		  box = b
		  done()

      afterEach (andDone) ->
	cleanupContainer stratName, 'mclovins-container-1', stratValue.disk, '15001', stratValue.selectedVG, andDone

      it 'return current used and the box limit in megabytes', (done) ->
	box.quota (err, stats) ->
	  expect(stats.used).to.match /\d+.*\d*/
	  if stratName == "lvm"
	    # somehow lvm reported about 105mb off
	    expect(stats.limit).to.be.closeTo 2 * 1024 * 1024, 110000
	  else
	    # somehow repquota reported number is off: 2049M instead of 2048M
	    expect(stats.limit).to.be.closeTo 2 * 1024 * 1024, 5000
          done()

    describe '#info', ->
      box = null

      context 'when box is running', ->
	beforeEach (done) ->
	  cleanupContainer stratName, 'mclovins-container-1', stratValue.disk, '15001', stratValue.selectedVG, ->
	    createContainer stratName, "1", "mclovins-container", "192.168.254.2", "10000", stratValue.disk, "15001", (err) ->
	      return done(err) if err
	      cleanDB ->
		settings = require('../../config/settings')
		redisStoreSettings = settings.redisStore
		redis = initRedisClientWith(redisStoreSettings)
		boxJSON = _.extend stratValue, {
		  id: 1
		  name: "mclovins-container"
		  ip: "192.168.254.2"
		  port: 10000
		  diskSpace: "1G"
		  memory: "256M"
		  containerTemplate: "test_container_template"
		  containerState: "running"
		}
		redis.hset 'aio:boxes', "mclovins-container-1", JSON.stringify(boxJSON), ->
		  Box.find "mclovins-container-1", (err, b) ->
		    box = b
		    done()

	afterEach (andDone) ->
	  cleanupContainer stratName, 'mclovins-container-1', stratValue.disk, '15001', stratValue.selectedVG, andDone

	it 'returns memory usage, disk usage and LXC status', (done) ->
	  box.info (err, info) ->
	    expect(info.storageUsage).to.match /([0-9]+\.*)?/
	    expect(info.memoryUsage).to.match /([0-9]+\.*)?/
	    expect(info.lxcStatus).to.eql "RUNNING"
	    done()

      context 'when box is stopped', ->
	beforeEach (done) ->
	  cleanupContainer stratName, 'mclovins-container-1', stratValue.disk, '15001', stratValue.selectedVG, ->
	    createContainer stratName, "1", "mclovins-container", "192.168.254.2", "10000", stratValue.disk, "15001", "dont-start", (err) ->
	      return done(err) if err
	      cleanDB ->
		settings = require('../../config/settings')
		redisStoreSettings = settings.redisStore
		redis = initRedisClientWith(redisStoreSettings)
		boxJSON = _.extend stratValue, {
		  id: 1
		  name: "mclovins-container"
		  ip: "192.168.254.2"
		  port: 10000
		  diskSpace: "1G"
		  memory: "256M"
		  containerTemplate: "test_container_template"
		  containerState: "stopped"
		}
		redis.hset 'aio:boxes', "mclovins-container-1", JSON.stringify(boxJSON), ->
		  Box.find "mclovins-container-1", (err, b) ->
		    box = b
		    done()

	afterEach (andDone) ->
	  cleanupContainer stratName, 'mclovins-container-1', stratValue.disk, '15001', stratValue.selectedVG, andDone

	it 'returns memory usage, disk usage and LXC status', (done) ->
	  box.info (err, info) ->
	    expect(info.storageUsage).to.match /([0-9]+\.*)?/
	    expect(info.memoryUsage).to.eql 0
	    expect(info.lxcStatus).to.eql "STOPPED"
	    done()

  # start running tests sequentially here
  tests = _.map strategies, (stratValue, stratName) -> (cb) -> testSuite(stratValue, stratName, cb)
  async.series tests, (err) -> console.log(err) if err
