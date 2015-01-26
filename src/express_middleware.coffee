module.exports = class ExpressMiddleware
  constructor: (@rateLimiter, @options = {}) ->

  extractIps: (req) ->
    [req.ip]

  weight: (req) ->
    1

  middleware: (options, callback) ->
    [callback, options] = [options, {}] unless callback

    # Pull out and default extraction functions
    {extractIps, weight} = options
    extractIps or= @extractIps
    weight or= @weight

    (req, res, next) =>
      @rateLimiter.incr extractIps(req), weight(req),
        (err, isLimited) =>
          if err
            if @options.ignoreRedisErrors
              isLimited = false
            else
              return next err

          return callback req, res, next if isLimited
          next()
