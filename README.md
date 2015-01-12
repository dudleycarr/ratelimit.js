RateLimit.js
============
[![Build
Status](https://travis-ci.org/dudleycarr/ratelimit.js.svg)](https://travis-ci.org/dudleycarr/ratelimit.js)

A NodeJS library for rate limiting using sliding windows stored in Redis.

### Express Middleware

Construct rate limiter and middleware instances:

```javascript
var RateLimit = require('ratelimit.js').RateLimit;
var ExpressMiddleware = require('ratelimit.js').ExpressMiddleware;
var redis = require('redis');

var rateLimiter = new RateLimit(redis.createClient(), [{interval: 1, limit: 10}]);
var limitMiddleware = new ExpressMiddleware(rateLimiter);
```

Rate limit every endpoint of an express application:

```javascript
app.use(limitMiddleware.trackRequests());

app.use(limitMiddleware.checkRequest(function(req, res, next) {
  res.status(429).json({message: 'rate limit exceeded'});
}));
```

Rate limit specific endpoints:

```javascript
app.use(limitMiddleware.trackRequests());

var limitEndpoint = limitMiddleware.checkRequest(function(req, res, next) {
  res.status(429).json({message: 'rate limit exceeded'});
});

app.get('/rate_limited', limitEndpoint, function(req, res, next) {
  // request is not rate limited...
});

app.post('/another_rate_limited', limitEndpoint, function(req, res, next) {
  // request is not rate limited...
});
```

Don't want to deny requests that are rate limited? Not sure why, but go ahead:

```javascript
app.use(limitMiddleware.trackRequests());

app.use(limitMiddleware.checkRequest(function(req, res, next) {
  req.rateLimited = true;
  next();
}));
```

Use a custom IP extraction function:

```javascript
function extractIps(req) {
  return req.ips;
}

app.use(limitMiddleware.trackRequests(extractIps));

app.use(limitMiddleware.checkRequest(extractIps, function(req, res, next) {
  res.status(429).json({message: 'rate limit exceeded'});
}));
```

Note: this is helpful if your application sits behind a proxy (or set of proxies).
[Read more about express, proxies and req.ips here](http://expressjs.com/guide/behind-proxies.html).
