RateLimit = require '../src/rate_limit'
async = require 'async'
redis = require 'redis'

redisClient = redis.createClient()

# Cleanup redis after each test
afterEach (done) ->
  deleteAllKeys = (search, done) ->
    redisClient.keys search, (err, keys) ->
      return done err if err or not keys.length

      redisClient.del keys..., done

  async.parallel [
    (callback) ->
      deleteAllKeys "#{RateLimit.DEFAULT_PREFIX}:*", callback

    (callback) ->
      deleteAllKeys RateLimit.WHITELIST_KEY, callback

    (callback) ->
      deleteAllKeys RateLimit.BLACKLIST_KEY, callback

  ], done
