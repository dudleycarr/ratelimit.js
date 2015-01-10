RateLimit.js
============
[![Build
Status](https://travis-ci.org/dudleycarr/ratelimit.js.svg)](https://travis-ci.org/dudleycarr/ratelimit.js)

A NodeJS library for rate limiting using sliding windows stored in Redis.

### Express Middleware

Construct rate limiter and middleware instances:

```coffee
RateLimitjs = require 'ratelimit.js'
redis = require 'redis'
{RateLimit, ExpressMiddleware} = RateLimitjs

rateLimiter = new RateLimit redis.createClient(), [
  {interval: 1, limit: 10}
]
limitMiddleware = new ExpressMiddleware rateLimiter
```

Rate limit every endpoint of an express application:

```coffee
app.use limitMiddleware.trackRequests()

app.use limitMiddleware.checkRequest (req, res, next) ->
  res.status(429).json message: 'rate limit exceeded'
```

Rate limit specific endpoints:

```coffee
app.use limitMiddleware.trackRequests()

limitEndpoint = limitMiddleware.checkRequest (req, res, next) ->
  res.status(429).json message: 'rate limit exceeded'

app.get '/rate_limited', limitEndpoint, (req, res, next) ->
  # request is not rate limited...

app.post '/another_rate_limited', limitEndpoint, (req, res, next) ->
  # request is not rate limited...
```

Don't want to deny requests that are rate limited? Not sure why, but go ahead:

```coffee
app.use limitMiddleware.trackRequests()

app.use limitMiddleware.checkRequest (req, res, next) ->
  req.rateLimited = true
  next()
```

Use a custom IP extraction function:

```coffee
extractIps = (req) ->
  req.ips

app.use limitMiddleware.trackRequests extractIps

app.use limitMiddleware.checkRequest extractIps, (req, res, next) ->
  res.status(429).json message: 'rate limit exceeded'
```

Note: this is helpful if your application sits behind a proxy (or set of proxies).
[Read more about express, proxies and req.ips here](http://expressjs.com/guide/behind-proxies.html).
