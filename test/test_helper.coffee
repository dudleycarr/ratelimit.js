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
      deleteAllKeys 'ratelimit:*', callback

    (callback) ->
      deleteAllKeys 'whitelist', callback

    (callback) ->
      deleteAllKeys 'blacklist', callback

  ], done
