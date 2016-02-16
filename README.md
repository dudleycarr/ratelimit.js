RateLimit.js
============
[![Build
Status](https://travis-ci.org/dudleycarr/ratelimit.js.svg)](https://travis-ci.org/dudleycarr/ratelimit.js) [![npm version](https://badge.fury.io/js/ratelimit.js.svg)](http://badge.fury.io/js/ratelimit.js)

A NodeJS library for efficient rate limiting using sliding windows stored in Redis.

Features
--------
* Uses a sliding window for a rate limit rule
* Multiple rules per instance
* Multiple instances of RateLimit side-by-side for different categories of users.
* Whitelisting/blacklisting of keys
* Includes Express middleware

Background
----------
See this excellent articles on how the sliding window rate limiting with Redis
works:

* [Introduction to Rate Limiting with Redis Part 1](http://www.dr-josiah.com/2014/11/introduction-to-rate-limiting-with.html)
* [Introduction to Rate Limiting with Redis Part 2](http://www.dr-josiah.com/2014/11/introduction-to-rate-limiting-with_26.html)

For more information on the `weight` and `precision` options, see the second
blog post above.

Install
-------

```
npm install ratelimit.js
```

Usage
-----

Basic example:

```javascript
var RateLimit = require('ratelimit.js').RateLimit;
var redis = require('redis');

var client = redis.createClient();

var rules = [
  {interval: 1, limit: 5},
  {interval: 3600, limit: 1000, precision: 100}
  ];
var limiter = new RateLimit(client, rules);

var showRateLimited = function(err, isRateLimited) {
  if (err) {
    return console.log("Error: " + err);
  }

  console.log("Is rate limited? " + isRateLimited);
};

// Exceed rate limit.
for(var i = 0; i < 10; i++) {
  limiter.incr('127.0.0.1', showRateLimited);
}
```


Output:
```
Is rate limited? false
Is rate limited? false
Is rate limited? false
Is rate limited? false
Is rate limited? false
Is rate limited? true
Is rate limited? true
Is rate limited? true
Is rate limited? true
Is rate limited? true
```

Constructor Usage:

```javascript
var RateLimit = require('ratelimit.js').RateLimit;
var redis = require('redis');

var client = redis.createClient();

var rules = [
  {interval: 3600, limit: 1000}
  ];

// You can define a prefix to be included on each redis entry
// This prevents collisions if you have multiple applications
// using the same redis db
var limiter = new RateLimit(client, rules, {prefix: 'RedisPrefix'});
```

**NOTE:** If your redis client supports transparent prefixing (like
[ioredis](https://github.com/luin/ioredis#transparent-key-prefixing))
the following configuration should be used:

```javascript
var limiter = new RateLimit(ioRedisClient, rules, {
  prefix: ioRedisClient.keyPrefix,
  clientPrefix: true
});
```

This will only include the prefix in the whitelist/blacklist keys passed to
the Lua scripts to be executed.

Whitelist/Blacklist Usage
-------------------------

You can whitelist or blacklist a set of keys to enforce automatically allowing all actions
(whitelisting) or automatically denying all actions (blacklisting). Whitelists and blacklists
do not expire so they can be used to allow or limit actions indefinitely.

Add to or remove from the whitelist:

```javascript
var RateLimit = require('ratelimit.js').RateLimit;
var redis = require('redis');
var rateLimiter = new RateLimit(redis.createClient(), [{interval: 1, limit: 10}]);

rateLimiter.whitelist(['127.0.0.1'], console.log);
rateLimiter.unwhitelist(['127.0.0.1'], console.log);
```

Add to or remove from the blacklist:

```javascript
var RateLimit = require('ratelimit.js').RateLimit;
var redis = require('redis');
var rateLimiter = new RateLimit(redis.createClient(), [{interval: 1, limit: 10}]);

rateLimiter.blacklist(['127.0.0.1'], console.log);
rateLimiter.unblacklist(['127.0.0.1'], console.log);
```

Express Middleware Usage
------------------------

Construct rate limiter and middleware instances:

```javascript
var RateLimit = require('ratelimit.js').RateLimit;
var ExpressMiddleware = require('ratelimit.js').ExpressMiddleware;
var redis = require('redis');

var rateLimiter = new RateLimit(redis.createClient(), [{interval: 1, limit: 10}]);

var options = {
  ignoreRedisErrors: true; // defaults to false
};
var limitMiddleware = new ExpressMiddleware(rateLimiter, options);
```

Rate limit every endpoint of an express application:

```javascript
app.use(limitMiddleware.middleware(function(req, res, next) {
  res.status(429).json({message: 'rate limit exceeded'});
}));
```

Rate limit specific endpoints:

```javascript
var limitEndpoint = limitMiddleware.middleware(function(req, res, next) {
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
app.use(limitMiddleware.middleware(function(req, res, next) {
  req.rateLimited = true;
  next();
}));
```

Use custom IP extraction and request weight functions:

```javascript
function extractIps(req) {
  return req.ips;
}

function weight(req) {
  return Math.round(Math.random() * 100);
}

var options = {
  extractIps: extractIps,
  weight: weight
};

app.use(limitMiddleware.middleware(options, function(req, res, next) {
  res.status(429).json({message: 'rate limit exceeded'});
}));
```

Note: this is helpful if your application sits behind a proxy (or set of proxies).
[Read more about express, proxies and req.ips here](http://expressjs.com/guide/behind-proxies.html).

ChangeLog
---------
* **1.7.1**
  * Refactor whitelist/blacklist lua code to be simpler and slightly more performant
* **1.7.0**
  * Fixed issue with whitelist and blacklist entries not being prefixed. Properly document prefix feature.
* **1.6.2**
  * Add support for precision property in rules objects
* **1.6.1**
  * Remove unused redis require
* **1.6.0**
  * Add support for whitelisting and blacklisting keys
* **1.5.0**
  * Add `weight` functionality to `ExpressMiddleware`
  * `ExpressMiddleware.middleware` now takes an options object instead of just `extractIps`
* **1.4.0**
  * Add `violatedRules` to RateLimit class to return the set of rules a key has violated
* **1.3.1**
  * Small fix to `middleware` function in `ExpressMiddleware`
* **1.3.0**
  * Add options to ExpressMiddleware constructor and support ignoring redis level errors
* **1.2.0**
  * Remove `checkRequest` and `trackRequests` from middleware in favor of single `middleware` function
* **1.1.0**
  * Add Express middleware
  * Updated README
  * Added credits on Lua code
* **1.0.0**
  * Initial RateLimit support

Authors
-------

* [Dudley Carr](https://github.com/dudleycarr)
* [Josh Gummersall](https://github.com/joshgummersall)
