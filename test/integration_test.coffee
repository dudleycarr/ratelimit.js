async = require 'async'
should = require 'should'
child_process = require 'child_process'
redis = require 'redis'
RateLimit = require '../src/index'

describe 'RateLimit', ->
  redisClient = null
  redisProcess = null
  ratelimit = null

  before (done) ->
    # Start Redis
    redisProcess = child_process.spawn 'redis-server',
      stdio: ['ignore', 'ignore', 'ignore']

    setTimeout done, 500

  after ->
    # Shutdown Redis
    redisProcess.kill()

  beforeEach ->
    redisClient = redis.createClient()
    rules = [
      {interval: 1, limit: 10}
      {interval: 60, limit: 50}
    ]
    ratelimit = new RateLimit redisClient, rules
  
  afterEach (done) ->
    # Delete all keys
    redisClient.keys 'ratelimit:*', (err, keys) ->
      redisClient.del keys... if keys.length > 0
    done()

  # Increment and response should not be limited.
  incrAndFalse = (num, callback) ->
    ratelimit.incr ['127.0.0.1'], 1, (err, isLimited) ->
      isLimited.should.eql false
      callback err

  incrAndTrue = (num, callback) ->
    ratelimit.incr ['127.0.0.1'], 1, (err, isLimited) ->
      isLimited.should.eql true
      callback err

  # Increment N times AND all responses should not be limited.
  bump = (num, callback) ->
    async.each [0...num], incrAndFalse, (err) ->
      callback err

  describe 'incr', ->

    it 'should not rate limit provided below rule rates', (done) ->
      bump 8, (err) ->
        done err

    it 'should not rate limit when continually below limits', (done) ->
      this.timeout 10000
      rules = [
        {interval: 1, limit: 10}
        {interval: 60, limit: 100}
      ]
      ratelimit = new RateLimit redisClient, rules

      everySec = (callback) ->
        bump 9, ->
          setTimeout callback, 1000

      async.series (everySec for i in [0...5]), done

    it 'should rate limit when over 10 req/sec', (done) ->
      bump 10, (err) ->
        ratelimit.incr ['127.0.0.1'], 1, (err, isLimited) ->
          isLimited.should.eql true
          done err

    it 'should rate limit when over 20 req/min', (done) ->
      async.series [
        # Do 10 requests
        (callback) ->
          bump 10, callback
        # Wait a second
        (callback) ->
          setTimeout callback, 1000
        # Do another 10 requests
        (callback) ->
          bump 10, callback
        # Do one more request to put us over the top for the 2nd rule
        (callback) ->
          incrAndTrue null, done
        ], (err) ->
          done err

  describe 'check', ->
    it 'should not be limited if the key does not exist', (done) ->
      ratelimit.check '127.0.0.1', (err, isLimited) ->
        isLimited.should.eql false
        done()

    it 'should return true if it has been limited', (done) ->
      bump 10, (err) ->
        incrAndTrue null, (err) ->
          ratelimit.check '127.0.0.1', (err, isLimited) ->
            isLimited.should.be.eql true
            done()
