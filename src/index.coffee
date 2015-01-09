EvalSha = require 'redis-evalsha'
_ = require 'underscore'
async = require 'async'
fs = require 'fs'
redis = require 'redis'

module.exports = class RateLimit

  constructor: (@redisClient, rules, @prefix = 'ratelimit') ->
    @checkFn = 'check_rate_limit'
    @checkIncrFn = 'check_incr_rate_limit'

    @eval = new EvalSha @redisClient
    @eval.add @checkFn, @checkLimitScript()
    @eval.add @checkIncrFn, @checkLimitIncrScript()

    @rules = @convertRules rules

  readLua: (filename) ->
    fs.readFileSync("#{__dirname}/../lua/#{filename}.lua").toString()

  checkLimitScript: ->
    [
      @readLua 'unpack_args'
      @readLua 'check_limit'
      'return 0'
    ].join '\n'

  checkLimitIncrScript: ->
    [
      @readLua 'unpack_args'
      @readLua 'check_limit'
      @readLua 'check_incr_limit'
    ].join '\n'

  convertRules: (rules) ->
    for rule in rules
      [rule.interval, rule.limit]

  scriptArgs: (keys, weight = 1) ->
    # Keys has to be a list
    adjustedKeys = if _.isArray(keys) then keys else [keys]
    adjustedKeys = _.chain(adjustedKeys)
      .compact()
      .filter(_.isString)
      .filter (key) ->
        key.length > 0
      .map (key) =>
        "#{@prefix}:#{key}"
      .value()

    throw new Error "Bad keys: #{keys}" if adjustedKeys.length is 0

    rules = JSON.stringify @rules
    ts = Math.floor(Date.now() / 1000)
    [adjustedKeys, [rules, ts, weight]]

  check: (keys, callback) ->
    try
      [keys, args] = @scriptArgs keys
      @eval.exec @checkFn, keys, args, (err, result) ->
        callback err, result is 1
    catch err
      callback err

  incr: (keys, weight, callback) ->
    try
      # Weight is optional.
      [weight, callback] = [1, weight] if arguments.length is 2
      [keys, args] = @scriptArgs keys, weight
      @eval.exec @checkIncrFn, keys, args, (err, result) ->
        callback err, result is 1
    catch err
      callback err

  keys: (callback) ->
    @redisClient.keys "#{@prefix}:*", (err, results) =>
      return callback err if err
      re = new RegExp("#{@prefix}:(.+)")
      keys = (re.exec(key)[1] for key in results)
      callback err, keys

  limitedKeys: (callback) ->
    @keys (err, keys) =>
      return callback err if err
      fn = (key, callback) =>
        @check key, (err, limited) ->
          callback limited
      async.filter keys, fn, (results) ->
        callback null, results
