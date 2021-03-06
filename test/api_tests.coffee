if Meteor.isServer
  Meteor.startup ->

    describe 'An API', ->
      context 'that hasn\'t been configured', ->
        it 'should have default settings', (test) ->
          test.equal Restivus.config.apiPath, 'api/'
          test.isFalse Restivus.config.useAuth
          test.isFalse Restivus.config.prettyJson
          test.equal Restivus.config.auth.token, 'services.resume.loginTokens.token'

        it 'should allow you to add an unconfigured route', (test) ->
          Restivus.addRoute 'test1', {authRequired: true, roleRequired: 'admin'},
            get: ->
              1

          route = Restivus.routes[0]
          test.equal route.path, 'test1'
          test.equal route.endpoints.get(), 1
          test.isTrue route.options.authRequired
          test.equal route.options.roleRequired, 'admin'
          test.isUndefined route.endpoints.get.authRequired
          test.isUndefined route.endpoints.get.roleRequired

        it 'should allow you to add an unconfigured collection route', (test) ->
          Restivus.addCollection new Mongo.Collection('tests'),
            routeOptions:
              authRequired: true
              roleRequired: 'admin'
            endpoints:
              getAll:
                action: ->
                  2

          route = Restivus.routes[1]
          test.equal route.path, 'tests'
          test.equal route.endpoints.get.action(), 2
          test.isTrue route.options.authRequired
          test.equal route.options.roleRequired, 'admin'
          test.isUndefined route.endpoints.get.authRequired
          test.isUndefined route.endpoints.get.roleRequired

        it 'should be configurable', (test) ->
          Restivus.configure
            apiPath: 'api/v1'
            useAuth: true
            auth: token: 'apiKey'

          config = Restivus.config
          test.equal config.apiPath, 'api/v1/'
          test.equal config.useAuth, true
          test.equal config.auth.token, 'apiKey'

      context 'that has been configured', ->
        it 'should not allow reconfiguration', (test) ->
          test.throws Restivus.configure, 'Restivus.configure() can only be called once'

        it 'should configure any previously added routes', (test) ->
          route = Restivus.routes[0]
          test.equal route.endpoints.get.action(), 1
          test.isTrue route.endpoints.get.authRequired
          test.equal route.endpoints.get.roleRequired, ['admin']

        it 'should configure any previously added collection routes', (test) ->
          route = Restivus.routes[1]
          test.equal route.endpoints.get.action(), 2
          test.isTrue route.endpoints.get.authRequired
          test.equal route.endpoints.get.roleRequired, ['admin']

    describe 'A collection route', ->
      it 'should be able to exclude endpoints using just the excludedEndpoints option', (test, next) ->
        Restivus.addCollection new Mongo.Collection('tests2'),
          excludedEndpoints: ['get', 'getAll']
#          endpoints:
#            post: false


        HTTP.get 'http://localhost:3000/api/v1/tests2/10', (error, result) ->
          response = JSON.parse result.content
          test.isTrue error
          test.equal result.statusCode, 404
          test.equal response.status, 'error'
          test.equal response.message, 'API endpoint not found'

        HTTP.get 'http://localhost:3000/api/v1/tests2/', (error, result) ->
          response = JSON.parse result.content
          test.isTrue error
          test.equal result.statusCode, 404
          test.equal response.status, 'error'
          test.equal response.message, 'API endpoint not found'
          next()

    describe 'An endpoint', ->

      it 'should cause an error when it returns null', (test, next) ->
        Restivus.addRoute 'testNullResponse',
          get: ->
            null

        HTTP.get 'http://localhost:3000/api/v1/testNullResponse', (error, result) ->
          test.isTrue error
          test.equal result.statusCode, 500
          next()

      it 'should cause an error when it returns undefined', (test, next) ->
        Restivus.addRoute 'testUndefinedResponse',
          get: ->
            undefined

        HTTP.get 'http://localhost:3000/api/v1/testUndefinedResponse', (error, result) ->
          test.isTrue error
          test.equal result.statusCode, 500
          next()

      it 'should be able to handle it\'s response manually', (test, next) ->
        Restivus.addRoute 'testManualResponse',
          get: ->
            @response.write 'Testing manual response.'
            @response.end()
            @done()

        HTTP.get 'http://localhost:3000/api/v1/testManualResponse', (error, result) ->
          response = result.content

          test.equal result.statusCode, 200
          test.equal response, 'Testing manual response.'
          next()

      it 'should not have to call this.response.end() when handling the response manually', (test, next) ->
        Restivus.addRoute 'testManualResponseNoEnd',
          get: ->
            @response.write 'Testing this.end()'
            @done()

        HTTP.get 'http://localhost:3000/api/v1/testManualResponseNoEnd', (error, result) ->
          response = result.content

          test.isFalse error
          test.equal result.statusCode, 200
          test.equal response, 'Testing this.end()'
          next()

      it 'should be able to send it\'s response in chunks', (test, next) ->
        Restivus.addRoute 'testChunkedResponse',
          get: ->
            @response.write 'Testing '
            @response.write 'chunked response.'
#            @done()

        HTTP.get 'http://localhost:3000/api/v1/testChunkedResponse', (error, result) ->
          response = result.content

          test.equal result.statusCode, 200
          test.equal response, 'Testing chunked response.'
          next()

      it 'should respond with an error if this.done() isn\'t called after response is handled manually', (test, next) ->
        Restivus.addRoute 'testManualResponseWithoutDone',
          get: ->
            undefined

        HTTP.get 'http://localhost:3000/api/v1/testManualResponseWithoutDone', (error, result) ->
          test.isTrue error
          test.equal result.statusCode, 500
          next()


#      context 'that has been authenticated', ->
#        it 'should have access to this.user and this.userId', (test) ->
