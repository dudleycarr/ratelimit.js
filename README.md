RateLimit.js
============
[![Build
Status](https://travis-ci.org/dudleycarr/ratelimit.js.svg)](https://travis-ci.org/dudleycarr/ratelimit.js)

A NodeJS library for rate limiting using sliding windows stored in Redis.

### Express Middleware

Rate limit every endpoint of an express application:

```coffee
app.use ratelimit.trackRequests()

app.use ratelimit.checkRequest (req, res) ->
  res.status(500).json message: 'rate limit exceeded'
```

Rate limit specific endpoints:

```coffee
app.use ratelimit.trackRequests()

limitEndpoint = ratelimit.checkRequest (req, res) ->
  res.status(500).json message: 'rate limit exceeded'

app.get '/rate_limited', limitEndpoint, (req, res, next) ->
  # request is not rate limited...

app.post '/another_rate_limited', limitEndpoint, (req, res, next) ->
  # request is not rate limited...
```

Use a custom IP extraction function:

```coffee
extractIps = (req) ->
  req.ips

app.use ratelimit.trackRequests extractIps

app.use ratelimit.checkRequest extractIps, (req, res) ->
  res.status(500).json message: 'rate limit exceeded'
```

Note: this is helpful if your application sits behind a proxy (or set of proxies).
[Read more about express, proxies and req.ips here](http://expressjs.com/guide/behind-proxies.html).
