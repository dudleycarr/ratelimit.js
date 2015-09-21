EvalSha = require 'redis-evalsha'
_ = require 'underscore'
async = require 'async'
fs = require 'fs'

module.exports = class RateLimit
  @DEFAULT_PREFIX: 'ratelimit'

  # Note: 1 is returned for a normal rate limited action, 2 is returned for a
  # blacklisted action. Must sync with return codes in lua/check_limit.lua
  @DENIED_NUMS: [1, 2]

  constructor: (@redisClient, rules, @prefix = @constructor.DEFAULT_PREFIX) ->
    @checkFn = 'check_rate_limit'
    @checkIncrFn = 'check_incr_rate_limit'

    @eval = new EvalSha @redisClient
    @eval.add @checkFn, @checkLimitScript()
    @eval.add @checkIncrFn, @checkLimitIncrScript()

    @rules = @convertRules rules

  readLua: (filename) ->
    fs.readFileSync "#{__dirname}/../lua/#{filename}.lua", 'utf8'

  checkLimitScript: ->
    [
      @readLua 'unpack_args'
      @readLua 'check_whitelist'
      @readLua 'check_blacklist'
      @readLua 'check_limit'
      'return 0'
    ].join '\n'

  checkLimitIncrScript: ->
    [
      @readLua 'unpack_args'
      @readLua 'check_whitelist'
      @readLua 'check_blacklist'
      @readLua 'check_limit'
      @readLua 'check_incr_limit'
    ].join '\n'

  convertRules: (rules) ->
    for rule in rules
      [rule.interval, rule.limit]

  whitelistKey: ->
    [@prefix, 'whitelist'].join ':'

  blacklistKey: ->
    [@prefix, 'blacklist'].join ':'

  scriptArgs: (keys, weight = 1) ->
    # Keys has to be a list
    adjustedKeys = _.chain([keys])
      .flatten()
      .compact()
      .filter (key) ->
        _.isString(key) and key.length
      .map (key) =>
        "#{@prefix}:#{key}"
      .value()

    throw new Error "Bad keys: #{keys}" unless adjustedKeys.length

    rules = JSON.stringify @rules
    ts = Math.floor Date.now() / 1000
    weight = Math.max weight, 1
    [adjustedKeys, [rules, ts, weight, @whitelistKey(), @blacklistKey()]]

  check: (keys, callback) ->
    try
      [keys, args] = @scriptArgs keys
    catch err
      return callback err

    @eval.exec @checkFn, keys, args, (err, result) =>
      callback err, result in @constructor.DENIED_NUMS

  incr: (keys, weight, callback) ->
    # Weight is optional.
    [weight, callback] = [1, weight] if arguments.length is 2
    try
      [keys, args] = @scriptArgs keys, weight
    catch err
      return callback err

    @eval.exec @checkIncrFn, keys, args, (err, result) =>
      callback err, result in @constructor.DENIED_NUMS

  keys: (callback) ->
    @redisClient.keys "#{@prefix}:*", (err, results) =>
      return callback err if err

      re = new RegExp "#{@prefix}:(.+)"
      keys = (re.exec(key)[1] for key in results)
      callback null, keys

  violatedRules: (keys, callback) ->
    checkKey = (key, callback) =>
      checkRule = (rule, callback) =>
        # Note: this mirrors precision computation in `check_limit.lua`
        # on lines 7 and 8 and count key construction on line 16
        [interval, limit, precision] = rule
        precision = Math.min (precision ? interval), interval
        countKey = "#{interval}:#{precision}:"

        @redisClient.hget "#{@prefix}:#{key}", countKey, (err, count = -1) ->
          return callback() unless count >= limit
          callback null, {interval, limit}

      async.map @rules, checkRule, (err, violatedRules) ->
        callback err, _.compact violatedRules

    async.concat _.flatten([keys]), checkKey, callback

  limitedKeys: (callback) ->
    @keys (err, keys) =>
      return callback err if err

      fn = (key, callback) =>
        @check key, (err, limited) ->
          callback limited
      async.filter keys, fn, (results) ->
        callback null, results

  whitelist: (keys, callback) ->
    whitelist = (key, callback) =>
      key = [@prefix, key].join ':'
      async.series [
        (callback) =>
          @redisClient.srem @blacklistKey(), key, callback

        (callback) =>
          @redisClient.sadd @whitelistKey(), key, callback

      ], callback

    async.each keys, whitelist, callback

  unwhitelist: (keys, callback) ->
    unwhitelist = (key, callback) =>
      key = [@prefix, key].join ':'
      @redisClient.srem @whitelistKey(), key, callback

    async.each keys, unwhitelist, callback

  blacklist: (keys, callback) ->
    blacklist = (key, callback) =>
      key = [@prefix, key].join ':'
      async.series [
        (callback) =>
          @redisClient.srem @whitelistKey(), key, callback

        (callback) =>
          @redisClient.sadd @blacklistKey(), key, callback

      ], callback

    async.each keys, blacklist, callback

  unblacklist: (keys, callback) ->
    unblacklist = (key, callback) =>
      key = [@prefix, key].join ':'
      @redisClient.srem @blacklistKey(), key, callback

    async.each keys, unblacklist, callback
