RateLimit = require '../src/index'
_ = require 'underscore'
async = require 'async'
child_process = require 'child_process'
redis = require 'redis'
should = require 'should'

describe 'RateLimit', ->
  redisClient = null
  ratelimit = null

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
      redisClient.del keys... if keys.length
    done()

  incrAndCheck = (num, value, callback) ->
    ratelimit.incr ['127.0.0.1'], 1, (err, isLimited) ->
      isLimited.should.eql value
      callback err

  # Increment and response should not be limited.
  incrAndFalse = _.partial incrAndCheck, _, false
  incrAndTrue = _.partial incrAndCheck, _, true

  # Increment N times AND all responses should not be limited.
  bump = (num, incrFn, callback) ->
    async.times num, incrFn, callback 

  describe 'incr', ->

    it 'should not rate limit provided below rule rates', (done) ->
      bump 8, incrAndFalse, done

    it 'should not rate limit when continually below limits', (done) ->
      @timeout 10000
      rules = [
        {interval: 1, limit: 10}
        {interval: 60, limit: 100}
      ]
      ratelimit = new RateLimit redisClient, rules

      everySec = (sec, callback) ->
        bump 9, incrAndFalse, ->
          setTimeout callback, 1000

      async.timesSeries 5, everySec, done

    it 'should rate limit when over 10 req/sec', (done) ->
      bump 10, incrAndFalse, (err) ->
        ratelimit.incr ['127.0.0.1'], 1, (err, isLimited) ->
          isLimited.should.eql true
          done err

    it 'should rate limit when over 20 req/min', (done) ->
      async.series [
        # Do 10 requests
        (callback) ->
          bump 10, incrAndFalse, callback
        # Wait a second
        (callback) ->
          setTimeout callback, 1000
        # Do another 10 requests
        (callback) ->
          bump 10, incrAndFalse, callback
        # Do one more request to put us over the top for the 2nd rule
        (callback) ->
          incrAndTrue null, done
        ], (err) ->
          done err

  describe 'check', ->
    it 'should not be limited if the key does not exist', (done) ->
      bump 1, incrAndFalse, done

    it 'should return true if it has been limited', (done) ->
      async.series [
        (callback) ->
          bump 10, incrAndFalse, callback
        (callback) ->
          bump 1, incrAndTrue, callback
        (callback) ->
          ratelimit.check '127.0.0.1', (err, isLimited) ->
            isLimited.should.be.ok
            callback()
      ], done
