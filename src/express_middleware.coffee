module.exports = class ExpressMiddleware
  constructor: (@rateLimiter, @options = {}) ->

  getIdentifiers: (req) ->
    [req.ip]

  weight: (req) ->
    1

  middleware: (options, callback) ->
    [callback, options] = [options, {}] unless callback

    # Pull out and default extraction functions
    {getIdentifiers, extractIps, weight} = options
    getIdentifiers or= extractIps # For backward-compatibility
    getIdentifiers or= @getIdentifiers

    weight or= @weight

    (req, res, next) =>
      @rateLimiter.incr getIdentifiers(req), weight(req),
        (err, isLimited) =>
          if err
            if @options.ignoreRedisErrors
              isLimited = false
            else
              return next err

          return callback req, res, next if isLimited
          next()
