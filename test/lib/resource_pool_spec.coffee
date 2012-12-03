ResourcePool = require '../../app/lib/resource_pool'
initRedisClientWith = require('../../app/lib/utils').initRedisClientWith

describe 'ResourcePool', ->
  client = settings = null
  resource =
    ip: '192.168.2.2'
    gateway: '192.168.2.1'
    interface: 'br-lxc-2'
    port: '10002'

  beforeEach ->
    settings = require('../../config/settings')
    client = initRedisClientWith(settings.redisStore)

  describe '.acquire', ->
    beforeEach (done) ->
      cleanDB(done)

    context 'when there are resources available', ->
      beforeEach (done) ->
        client.rpush 'available_resources', JSON.stringify(resource), (err, replies) ->
          done() if !err

      it 'should acquire a resource from the redis pool', (done) ->
        ResourcePool.acquire (err, res) ->
          res.should.eql resource
          done()

    context 'when no resource is available', ->
      beforeEach (done) ->
        cleanDB(done)

      it 'should return an error', (done) ->
        ResourcePool.acquire (err, res) ->
          err.should.be.an.instanceOf(Error)
          done()

  describe '.release', ->
    beforeEach (done) ->
      cleanDB(done)

    context 'when a resource is valid', (done) ->
      beforeEach (done) ->
        client.rpush 'used_resources', JSON.stringify(resource), (err, replies) ->
          done() if !err

      it 'should release the resource back to the pool', (done) ->
        ResourcePool.release resource, (err) =>
          multi = client.multi()
          multi.llen 'available_resources'
          multi.llen 'used_resources'

          multi.exec (err, replies) ->
            replies[0].should.eql 1
            replies[1].should.eql 0
            done()
