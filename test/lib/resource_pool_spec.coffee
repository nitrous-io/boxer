ResourcePool = require '../../app/lib/resource_pool'
initRedisClientWith = require('../../app/lib/utils').initRedisClientWith

describe 'ResourcePool', ->
  client = settings = null

  beforeEach ->
    settings = require('../../config/settings')
    client = initRedisClientWith(settings.redisStore)

  describe '.acquire', ->
    beforeEach (done) ->
      cleanDB(done)

    context 'when there are ports and ips available', ->
      beforeEach (done) ->
        multi = client.multi()
        multi.rpush 'available_ips', 254
        multi.rpush 'available_ports', 10000
        multi.exec (err, replies) ->
          done() if !err

      it 'should acquire an IP and a Port from the Redis Pool', (done) ->
        ResourcePool.acquire (err, resources) ->
          resources.ip.should.eql '254'
          resources.port.should.eql '10000'
          done()

    context 'when a port is available but an IP is not available', ->
      beforeEach (done) ->
        multi = client.multi()
        multi.rpush 'available_ports', 10000
        multi.exec (err, replies) ->
          done() if !err

      it 'should return an error', (done) ->
        ResourcePool.acquire (err, resources) ->
          err.should.be.an.instanceOf(Error)
          done()

    context 'when an IP is available but a port is not available', ->
      beforeEach (done) ->
        multi = client.multi()
        multi.rpush 'available_ips', 254
        multi.exec (err, replies) ->
          done() if !err

      it 'should return an error', (done) ->
        ResourcePool.acquire (err, resources) ->
          err.should.be.an.instanceOf(Error)
          done()

  describe '.release', ->
    beforeEach (done) ->
      cleanDB(done)

    context 'when ip and port are valid', (done) ->
      beforeEach (done) ->
        multi = client.multi()
        multi.rpush 'used_ips', '254'
        multi.rpush 'used_ports', '10000'
        multi.exec (err, replies) ->
          done() if !err

      it 'should release the ip and the port back to the pool', (done) ->
        ResourcePool.release {ip: '254', port: '10000'}, (err) =>
          multi = client.multi()
          multi.llen 'available_ips'
          multi.llen 'used_ips'
          multi.llen 'available_ports'
          multi.llen 'used_ports'

          multi.exec (err, replies) ->
            replies[0].should.eql 1
            replies[1].should.eql 0
            replies[2].should.eql 1
            replies[3].should.eql 0
            done()
