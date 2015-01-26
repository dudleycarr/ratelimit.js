module.exports = class ExpressMiddleware
  constructor: (@rateLimiter, @options = {}) ->

  extractIps: (req) ->
    [req.ip]

  extractWeight: (req) ->
    1

  middleware: (options, callback) ->
    [callback, options] = [options, {}] unless callback

    # Pull out and default extraction functions
    {extractIps, extractWeight} = options
    extractIps or= @extractIps
    extractWeight or= @extractWeight

    (req, res, next) =>
      @rateLimiter.incr extractIps(req), extractWeight(req),
        (err, isLimited) =>
          if err
            if @options.ignoreRedisErrors
              isLimited = false
            else
              return next err

          return callback req, res, next if isLimited
          next()
