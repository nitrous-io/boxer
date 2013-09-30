Box                 = require '../../app/lib/box'
ResourcePool        = require '../../app/lib/resource_pool'
childProcess        = require 'child_process'
scriptPath          = __dirname.replace('test/integration', 'scripts')
initRedisClientWith = require('../../app/lib/utils').initRedisClientWith

describe Box, ->
  describe ".find", ->
    it 'returns callback with error when we cant find the box', (done) ->
      callback = (err, box) =>
        expect(err).to.be.an.instanceof(Error)
        done()
      Box.find 'non-existent-box', callback

  describe '.startAll', ->
    beforeEach (done) ->
      childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container 1 mclovins-container-1 192.168.254.2 10000 dont-start", (err, stdout, stderr) ->
        done(err) if err
        childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container 2 mclovins-container-2 192.168.254.3 10001 dont-start", (err, stdout, stderr) ->
          done(err) if err
          childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container 3 mclovins-container-3 192.168.254.4 10002 dont-start", (err, stdout, stderr) ->
            done(err) if err

            cleanDB ->
              settings = require('../../config/settings')
              redisStoreSettings = settings.redisStore
              redis = initRedisClientWith(redisStoreSettings)
              redis.hset 'aio:boxes', "mclovins-container-1", '{"id":1,"name":"mclovins-container-1","mount":"lvm","ip":"192.168.254.2","port":10000,"diskSpace":"1G","memory":"256M","containerTemplate":"test_container_template","containerState":"running","disk":"/lxc/disk1"}', ->
                redis.hset 'aio:boxes', "mclovins-container-2", '{"id":2,"name":"mclovins-container-2","mount":"lvm","ip":"192.168.254.3","port":10001,"diskSpace":"1G","memory":"256M","containerTemplate":"test_container_template","containerState":"stopped","disk":"lxc/disk1"}', ->
                  redis.hset 'aio:boxes', "mclovins-container-3", '{"id":3,"name":"mclovins-container-3","mount":"lvm","ip":"192.168.254.4","port":10002,"diskSpace":"1G","memory":"256M","containerTemplate":"test_container_template","containerState":"running","disk": "/lxc/disk1"}', ->
                    Box.startAll done

    afterEach (done) ->
      cleanupContainer 'mclovins-container-1-1', '192.168.254.2', ->
        cleanupContainer 'mclovins-container-2-2', '192.168.254.3', ->
          cleanupContainer 'mclovins-container-3-3', '192.168.254.4', ->
            done()

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
      childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container 1 mclovins-container 192.168.254.2 10000 dont-start", (err, stdout, stderr) ->
        return done(err) if err
        cleanDB ->
          settings = require('../../config/settings')
          redisStoreSettings = settings.redisStore
          redis = initRedisClientWith(redisStoreSettings)
          redis.hset 'aio:boxes', "mclovins-container-1", JSON.stringify({
            id: 1
            name: "mclovins-container"
            ip: "192.168.254.2"
            port: 10000
            diskSpace: "1G"
            memory: "256M"
            containerTemplate: "test_container_template"
            state: "stopped"
            disk: "/lxc/disk1"
            mount: "lvm"
          }), ->
            Box.find "mclovins-container-1", (err, b) ->
              box = b
              done()

    afterEach (andDone) ->
      cleanupContainer 'mclovins-container-1', "192.168.254.2", andDone

    it 'return current used and the box limit in megabytes', (done) ->
      box.quota (err, stats) ->
        expect(stats.used).to.match /\d+.*\d+/
        expect(stats.limit).to.equal 2 * 1024 * 1024
        done()

  describe '#info', ->
    box = null

    context 'when box is running', ->
      beforeEach (done) ->
        childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container 1 mclovins-container 192.168.254.2 10000", (err, stdout, stderr) ->
          return done(err) if err
          cleanDB ->
            settings = require('../../config/settings')
            redisStoreSettings = settings.redisStore
            redis = initRedisClientWith(redisStoreSettings)
            redis.hset 'aio:boxes', "mclovins-container-1", JSON.stringify({
              id: 1
              name: "mclovins-container"
              ip: "192.168.254.2"
              port: 10000
              diskSpace: "1G"
              memory: "256M"
              containerTemplate: "test_container_template"
              state: "running"
              disk: "/lxc/disk1"
              mount: "lvm"
            }), ->
              Box.find "mclovins-container-1", (err, b) ->
                box = b
                done()

      afterEach (andDone) ->
        cleanupContainer 'mclovins-container-1', "192.168.254.2", andDone

      it 'returns memory usage, disk usage and LXC status', (done) ->
        box.info (err, info) ->
          expect(info.storageUsage).to.match /([0-9]+\.*)?/
          expect(info.memoryUsage).to.match /([0-9]+\.*)?/
          expect(info.lxcStatus).to.eql "RUNNING"
          done()

    context 'when box is stopped', ->
      beforeEach (done) ->
        childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container 1 mclovins-container 192.168.254.2 10000 dont-start", (err, stdout, stderr) ->
          return done(err) if err
          cleanDB ->
            settings = require('../../config/settings')
            redisStoreSettings = settings.redisStore
            redis = initRedisClientWith(redisStoreSettings)
            redis.hset 'aio:boxes', "mclovins-container-1", JSON.stringify({
              id: 1
              name: "mclovins-container"
              ip: "192.168.254.2"
              port: 10000
              diskSpace: "1G"
              memory: "256M"
              containerTemplate: "test_container_template"
              state: "stopped"
              disk: "/lxc/disk1"
              mount: "lvm"
            }), ->
              Box.find "mclovins-container-1", (err, b) ->
                box = b
                done()

      afterEach (andDone) ->
        cleanupContainer 'mclovins-container-1', "192.168.254.2", andDone

      it 'returns memory usage, disk usage and LXC status', (done) ->
        box.info (err, info) ->
          expect(info.storageUsage).to.match /([0-9]+\.*)?/
          expect(info.memoryUsage).to.eql 0
          expect(info.lxcStatus).to.eql "STOPPED"
          done()

