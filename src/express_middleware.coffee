module.exports = class ExpressMiddleware
  constructor: (@rateLimiter) ->

  extractIpsFromReq: (req) ->
    [req.ip]

  middleware: (extractIps, callback) ->
    [callback, extractIps] = [extractIps, null] unless callback
    extractIps or= @extractIpsFromReq
    (req, res, next) =>
      @rateLimiter.incr extractIps(req), (err, isLimited) ->
        return next err if err
        return callback req, res, next if isLimited
        next()
