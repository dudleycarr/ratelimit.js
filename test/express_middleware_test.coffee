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
