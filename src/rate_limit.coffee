EvalSha = require 'redis-evalsha'
_ = require 'underscore'
async = require 'async'
fs = require 'fs'

module.exports = class RateLimit
  @DEFAULT_PREFIX: 'ratelimit'

  # This is used to signify a request from a blacklisted identifier
  @BLACKLIST_NUMBER: 1

  constructor: (@redisClient, rules, @options = {}) ->
    # Support passing the prefix directly as the third parameter.
    if _.isString @options
      @options =
        prefix: @options

    # Enforce default prefix if none is defined. Note: use ?= to allow users
    # to specify an empty prefix. If you are using a redis library that
    # automatically prefixes keys then you might specify a blank prefix.
    @options.prefix ?= @constructor.DEFAULT_PREFIX

    # Used if the redis client passed in support transparent prefixing (like
    # ioredis). This is used for the white/blacklist keys passed to the Lua
    # scripts.
    @options.clientPrefix ?= false

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
      @readLua 'check_whitelist_blacklist'
      @readLua 'check_limit'
      'return 0'
    ].join '\n'

  checkLimitIncrScript: ->
    [
      @readLua 'unpack_args'
      @readLua 'check_whitelist_blacklist'
      @readLua 'check_limit'
      @readLua 'check_incr_limit'
    ].join '\n'

  convertRules: (rules) ->
    for {interval, limit, precision} in rules when interval and limit
      _.compact [interval, limit, precision]

  prefixKey: (key, force = false) ->
    parts = [key]

    # Support prefixing with an optional `force` argument, but omit prefix by
    # default if the client library supports transparent prefixing.
    parts.unshift @options.prefix if force or not @options.clientPrefix

    # The compact handles a falsy prefix
    _.compact(parts).join ':'

  whitelistKey: ->
    @prefixKey 'whitelist', true

  blacklistKey: ->
    @prefixKey 'blacklist', true

  scriptArgs: (keys, weight = 1) ->
    # Keys has to be a list
    adjustedKeys = _.chain([keys])
      .flatten()
      .compact()
      .filter (key) ->
        _.isString(key) and key.length
      .map (key) =>
        @prefixKey key
      .value()

    throw new Error "Bad keys: #{keys}" unless adjustedKeys.length

    rules = JSON.stringify @rules
    ts = Math.floor Date.now() / 1000
    weight = Math.max weight, 1
    [adjustedKeys, [rules, ts, weight, @whitelistKey(), @blacklistKey()]]

  handleResult: (callback) ->
    (err, result) =>
      return callback err if err

      if _.isNumber result
        return callback null, result is @constructor.BLACKLIST_NUMBER, []

      # If result is not a number, it's JSON that explains the current state
      # for the given keys.
      result = try
        JSON.parse result
      catch e
        []

      rulesState = []
      for [requests, violated, resetTs], i in result
        [interval, limit, precision] = @rules[i] or []

        rulesState.push {
          interval
          limit
          precision
          requests
          violated
          resetTs
        }

        return callback null, true, rulesState if violated

      callback null, false, rulesState

  check: (keys, callback) ->
    try
      [keys, args] = @scriptArgs keys
    catch err
      return callback err

    @eval.exec @checkFn, keys, args, @handleResult callback

  incr: (keys, weight, callback) ->
    # Weight is optional.
    [weight, callback] = [1, weight] if arguments.length is 2
    try
      [keys, args] = @scriptArgs keys, weight
    catch err
      return callback err

    @eval.exec @checkIncrFn, keys, args, @handleResult callback

  keys: (callback) ->
    @redisClient.keys @prefixKey('*'), (err, results) =>
      return callback err if err

      re = new RegExp @prefixKey '(.+)'
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

        @redisClient.hget @prefixKey(key), countKey, (err, count = -1) ->
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
      key = @prefixKey key
      async.series [
        (callback) =>
          @redisClient.srem @blacklistKey(), key, callback

        (callback) =>
          @redisClient.sadd @whitelistKey(), key, callback

      ], callback

    async.each keys, whitelist, callback

  unwhitelist: (keys, callback) ->
    unwhitelist = (key, callback) =>
      key = @prefixKey key
      @redisClient.srem @whitelistKey(), key, callback

    async.each keys, unwhitelist, callback

  blacklist: (keys, callback) ->
    blacklist = (key, callback) =>
      key = @prefixKey key
      async.series [
        (callback) =>
          @redisClient.srem @whitelistKey(), key, callback

        (callback) =>
          @redisClient.sadd @blacklistKey(), key, callback

      ], callback

    async.each keys, blacklist, callback

  unblacklist: (keys, callback) ->
    unblacklist = (key, callback) =>
      key = @prefixKey key
      @redisClient.srem @blacklistKey(), key, callback

    async.each keys, unblacklist, callback
