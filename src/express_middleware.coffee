module.exports = class ExpressMiddleware
  constructor: (@rateLimiter, @options = {}) ->

  extractIpsFromReq: (req) ->
    [req.ip]

  middleware: (extractIps, callback) ->
    [callback, extractIps] = [extractIps, null] unless callback
    extractIps or= @extractIpsFromReq
    (req, res, next) =>
      @rateLimiter.incr extractIps(req), (err, isLimited) =>
        if err
          if @options.ignoreRedisErrors
            isLimited = false
          else
            return next err

        return callback req, res, next if isLimited
        next()
