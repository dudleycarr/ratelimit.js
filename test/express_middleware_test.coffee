async = require 'async'
express = require 'express'
redis = require 'redis'
should = require 'should'
sinon = require 'sinon'
supertest = require 'supertest'
{RateLimit, ExpressMiddleware} = require '../src'

describe 'Express Middleware', ->
  beforeEach ->
    @sandbox = sinon.sandbox.create()

    # Set up rate limiter instance, mock, and middleware instance
    @redisClient = redis.createClient()
    @ratelimit = new RateLimit @redisClient, [
      {interval: 1, limit: 1}
    ]
    @ratelimitMock = @sandbox.mock @ratelimit
    @middleware = new ExpressMiddleware @ratelimit

    # Set up express and supertest for use throughout tests
    @app = express()
    middleware = @middleware.middleware (req, res, next) ->
      res.status(429).end()

    @app.get '/', middleware, (req, res, next) ->
      res.status(200).end()

    @request = =>
      supertest @app

  afterEach (done) ->
    @sandbox.restore()
    @ratelimit.keys (err, keys = []) =>
      return done err if err
      if keys.length
        @redisClient.del keys..., done
      else
        done()

  describe 'getIdentifiers', ->
    it 'should extract an IP from an express-style request', ->
      @middleware.getIdentifiers(ip: '127.0.0.1')
        .should.eql ['127.0.0.1']

  describe '.middleware', ->
    it 'should track a request IP', (done) ->
      @ratelimitMock.expects('incr')
        .withArgs(['127.0.0.1'])
        .once()
        .yields()

      @request().get('/').expect(200).end (err) =>
        @ratelimitMock.verify()
        done err

    it 'should allow the first request and limit the second', (done) ->
      async.series [
        (done) =>
          @request().get('/').expect(200).end done
        (done) =>
          @request().get('/').expect(429).end done
      ], done

    it 'should ignore a redis-level error', (done) ->
      @middleware.options.ignoreRedisErrors = true

      @ratelimitMock
        .expects('incr')
        .withArgs(['127.0.0.1'])
        .once()
        .yields new Error()

      @request().get('/').expect(200).end (err) =>
        @ratelimitMock.verify()
        done err

    it 'should support custom request weights', (done) ->
      weight = (req) ->
        10

      @ratelimitMock
        .expects('incr')
        .withArgs(['127.0.0.1'], 10)
        .once()
        .yields()

      weighted = @middleware.middleware {weight}, (req, res, next) ->
        res.status(429).end()

      @app.get '/weight', weighted, (req, res, next) ->
        res.status(200).end()

      @request().get('/weight').expect(200).end (err) =>
        @ratelimitMock.verify()
        done err

  describe '.middleware with headers option set', ->
    beforeEach ->
      @ratelimit = new RateLimit @redisClient, [
        interval: 3
        limit: 1
        precision: 1
      ]

      @ratelimitMock = @sandbox.mock @ratelimit
      @middleware = new ExpressMiddleware @ratelimit

      @app = express()
      middleware = @middleware.middleware headers: true, (req, res, next) ->
        res.status(429).end()

      @app.get '/', middleware, (req, res, next) ->
        res.status(200).end()

      @request = =>
        supertest @app

    it 'should include ratelimit response headers', (done) ->
      @request().get('/').expect(200).end (err, {headers} = {}) ->
        return done err if err

        should.exist headers['x-ratelimit-requests']
        headers['x-ratelimit-requests'].should.eql '1'

        should.exist headers['x-ratelimit-remaining']
        headers['x-ratelimit-remaining'].should.eql '0'

        should.exist headers['x-ratelimit-reset']

        done()

    it 'should not increase reset with each successive request', (done) ->
      @timeout 4000

      async.waterfall [
        (callback) =>
          @request().get('/').expect(200).end (err, {headers} = {}) ->
            return callback err if err

            should.exist headers['x-ratelimit-reset']
            setTimeout ->
              callback null, headers['x-ratelimit-reset']
            , 1500

        (resetTs, callback) =>
          @request().get('/').expect(429).end (err, {headers} = {}) =>
            return done err if err

            should.exist headers['x-ratelimit-reset']
            headers['x-ratelimit-reset'].should.eql resetTs
            callback()

      ], done

    it 'should have the correct reset ts', (done) ->
      @timeout 4000

      async.waterfall [
        (callback) =>
          @request().get('/').expect(200).end (err, {headers} = {}) ->
            return callback err if err

            should.exist headers['x-ratelimit-reset']
            setTimeout ->
              callback null, headers['x-ratelimit-reset']
            , 3300

        (resetTs, callback) =>
          @request().get('/').expect(200).end (err, {headers} = {}) =>
            return done err if err

            should.exist headers['x-ratelimit-reset']
            headers['x-ratelimit-reset'].should.not.eql resetTs
            callback()

      ], done
