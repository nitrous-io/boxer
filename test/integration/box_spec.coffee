Box                 = require '../../app/lib/box'
ResourcePool        = require '../../app/lib/resource_pool'
childProcess        = require 'child_process'
scriptPath          = __dirname.replace('test/integration', 'scripts')
initRedisClientWith = require('../../app/lib/utils').initRedisClientWith

describe Box, ->
  describe '.startAll', ->
    beforeEach (done) ->
      childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container 1 mclovins-container-1 192.168.254.2 10000 dont-start", timeout:5000, (err, stdout, stderr) ->
        done(err) if err
        childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container 2 mclovins-container-2 192.168.254.3 10001 dont-start", timeout:5000, (err, stdout, stderr) ->
          done(err) if err
          childProcess.exec "sudo #{scriptPath}/boxer-setup-test-container 3 mclovins-container-3 192.168.254.4 10002 dont-start", timeout:5000, (err, stdout, stderr) ->
            done(err) if err

            cleanDB ->
              settings = require('../../config/settings')
              redisStoreSettings = settings.redisStore
              redis = initRedisClientWith(redisStoreSettings)
              redis.hset 'aio:boxes', "mclovins-container-1", '{"id":1,"name":"mclovins-container-1","ip":"192.168.254.2","port":10000,"diskSpace":"1G","memory":"256M","containerTemplate":"test_container_template","containerState":"running"}', ->
                redis.hset 'aio:boxes', "mclovins-container-2", '{"id":2,"name":"mclovins-container-2","ip":"192.168.254.3","port":10001,"diskSpace":"1G","memory":"256M","containerTemplate":"test_container_template","containerState":"stopped"}', ->
                  redis.hset 'aio:boxes', "mclovins-container-3", '{"id":3,"name":"mclovins-container-3","ip":"192.168.254.4","port":10002,"diskSpace":"1G","memory":"256M","containerTemplate":"test_container_template","containerState":"running"}', ->
                    Box.startAll done

    afterEach (done) ->
      cleanupContainer 'mclovins-container-1-1', '192.168.254.2', ->
        cleanupContainer 'mclovins-container-2-2', '192.168.254.3', ->
          cleanupContainer 'mclovins-container-3-3', '192.168.254.4', ->
            done()

    it 'should start all boxes which have its containerState set to running', (done) ->
      childProcess.exec "sudo lxc-info -n mclovins-container-1-1", timeout: 5000, (err, stdout, stderr) ->
        expect(stdout).to.match /RUNNING/

        childProcess.exec "sudo lxc-info -n mclovins-container-2-2", timeout: 5000, (err, stdout, stderr) ->
          expect(stdout).to.match /STOPPED/

          childProcess.exec "sudo lxc-info -n mclovins-container-3-3", timeout: 5000, (err, stdout, stderr) ->
            expect(stdout).to.match /RUNNING/
            done()

