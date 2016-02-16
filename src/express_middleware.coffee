module.exports = class ExpressMiddleware
  constructor: (@rateLimiter, @options = {}) ->

  getIdentifiers: (req) ->
    [req.ip]

  weight: (req) ->
    1

  middleware: (options, callback) ->
    [callback, options] = [options, {}] unless callback

    # Pull out and default extraction functions
    {getIdentifiers, extractIps, weight, headers} = options
    getIdentifiers or= extractIps # For backward-compatibility
    getIdentifiers or= @getIdentifiers

    weight or= @weight
    headers or= @options.headers

    (req, res, next) =>
      @rateLimiter.incr getIdentifiers(req), weight(req),
        (err, isLimited, rulesState) =>
          if err
            if @options.ignoreRedisErrors
              isLimited = false
            else
              return next err

          req.ratelimitState = rulesState

          if headers
            # Find rule with the _least_ remaining available requests
            leastRemaining = rulesState?[0]
            leastRemainingReqs = leastRemaining.limit - leastRemaining.requests
            for ruleState in rulesState?[1..] or []
              if ruleState.limit - ruleState.requests < leastRemainingReqs
                leastRemaining = ruleState

            # This won't necessarily exist, esp. if the request is white-listed
            # or black-listed.
            if leastRemaining
              res.set 'x-ratelimit-requests', leastRemaining.limit
              res.set 'x-ratelimit-remaining', leastRemainingReqs
              res.set 'x-ratelimit-reset', leastRemaining.resetTs

          return callback req, res, next if isLimited
          next()
