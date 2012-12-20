ResourcePool = require '../../app/lib/resource_pool'
initRedisClientWith = require('../../app/lib/utils').initRedisClientWith

describe 'ResourcePool', ->
  client = settings = null
  ip = '192.168.2.2'
  resource =
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
        multi = client.multi()
        multi.rpush 'aio:available_resources', ip
        multi.hmset "aio:nwr:#{ip}", resource
        multi.exec (err, replies) ->
          done() if !err

      it 'should acquire a resource from the redis pool', (done) ->
        ResourcePool.acquire (err, res) ->
          res.ip.should.eql ip
          res.gateway.should.eql resource.gateway
          res.port.should.eql resource.port
          res.interface.should.eql resource.interface
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
        multi = client.multi()
        multi.rpush 'aio:used_resources', ip
        multi.hmset "aio:nwr:#{ip}", resource
        multi.exec (err, replies) ->
          done() if !err

      it 'should release the resource back to the pool', (done) ->
        resource.ip = ip

        ResourcePool.release resource, (err) =>
          multi = client.multi()
          multi.llen 'aio:available_resources'
          multi.llen 'aio:used_resources'

          multi.exec (err, replies) ->
            replies[0].should.eql 1
            replies[1].should.eql 0
            done()
