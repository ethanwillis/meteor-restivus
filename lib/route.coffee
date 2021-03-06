class @Route

  constructor: (@api, @path, @options, @endpoints) ->
    # Check if options were provided
    if not @endpoints
      @endpoints = @options
      @options = {}


  addToApi: ->
    self = this

    # Throw an error if a route has already been added at this path
    # TODO: Check for collisions with paths that follow same pattern with different parameter names
    if _.contains @api.config.paths, @path
      throw new Error "Cannot add a route at an existing path: #{@path}"

    # Configure each endpoint on this route
    @_resolveEndpoints()
    @_configureEndpoints()

    # Add the path to our list of existing paths
    @api.config.paths.push @path

    # Setup endpoints on route using Iron Router
    fullPath = @api.config.apiPath + @path
    Router.route fullPath,
      where: 'server'
      action: ->
        # Add parameters in the URL and request body to the endpoint context
        # TODO: Decide whether or not to nullify the copied objects. Makes sense to do it, right?
        @urlParams = @params
        @queryParams = @params.query
        @bodyParams = @request.body

        # Add function to endpoint context for indicating a response has been initiated manually
        @done = =>
          @_responseInitiated = true

        # Respond to the requested HTTP method if an endpoint has been provided for it
        method = @request.method
        if method is 'GET' and self.endpoints.get
          responseData = self._callEndpoint this, self.endpoints.get
        else if method is 'POST' and self.endpoints.post
          responseData = self._callEndpoint this, self.endpoints.post
        else if method is 'PUT' and self.endpoints.put
          responseData = self._callEndpoint this, self.endpoints.put
        else if method is 'PATCH' and self.endpoints.patch
          responseData = self._callEndpoint this, self.endpoints.patch
        else if method is 'DELETE' and self.endpoints.delete
          responseData = self._callEndpoint this, self.endpoints.delete
        else if method is 'OPTIONS' and self.endpoints.options
          responseData = self._callEndpoint this, self.endpoints.options
        else
          responseData = {statusCode: 404, body: {status: "error", message:'API endpoint not found'}}

        if responseData is null or responseData is undefined
          throw new Error "Cannot return null or undefined from an endpoint: #{method} #{fullPath}"
        if @response.headersSent and not @_responseInitiated
          throw new Error "Must call this.done() after handling endpoint response manually: #{method} #{fullPath}"

        if @_responseInitiated
          # Ensure the response is properly completed
          @response.end()
          return

        # Generate and return the http response, handling the different endpoint response types
        if responseData.body and (responseData.statusCode or responseData.headers)
          responseData.statusCode or= 200
          # TODO: Figure out why I can't use 'Content-Type'
          responseData.headers or= {'contenttype': 'text/json'}
          self._respond this, responseData.body, responseData.statusCode, responseData.headers
        else
          self._respond this, responseData


  ###
    Convert all endpoints on the given route into our expected endpoint object if it is a bare function

    @param {Route} route The route the endpoints belong to
  ###
  _resolveEndpoints: ->
    _.each @endpoints, (endpoint, method, endpoints) ->
      if _.isFunction(endpoint)
        endpoints[method] = {action: endpoint}
    return


  ###
    Configure the authentication and role requirement on an endpoint

    Once it's globally configured in the API, authentication can be required on an entire route or individual
    endpoints. If required on an entire route, that serves as the default. If required in any individual endpoints, that
    will override the default.

    After the endpoint is configured, all authentication and role requirements of an endpoint can be accessed at
    <code>endpoint.authRequired</code> and <code>endpoint.roleRequired</code>, respectively.

    @param {Route} route The route the endpoints belong to
    @param {Endpoint} endpoint The endpoint to configure
  ###
  _configureEndpoints: ->
    _.each @endpoints, (endpoint) ->
        # Configure acceptable roles
      if not @options?.roleRequired
        @options.roleRequired = []
      if not endpoint.roleRequired
        endpoint.roleRequired = []
      endpoint.roleRequired = _.union endpoint.roleRequired, @options.roleRequired
      # Make it easier to check if no roles are required
      if _.isEmpty endpoint.roleRequired
        endpoint.roleRequired = false

      # Configure auth requirement
      if not @api.config.useAuth
        endpoint.authRequired = false
      else if endpoint.authRequired is undefined
        if @options?.authRequired or endpoint.roleRequired
          endpoint.authRequired = true
        else
          endpoint.authRequired = false
      return
    , this
    return


  ###
    Authenticate an endpoint if required, and return the result of calling it

    @returns The endpoint response or a 401 if authentication fails
  ###
  _callEndpoint: (endpointContext, endpoint) ->
    # Call the endpoint if authentication doesn't fail
    if @_authAccepted endpointContext, endpoint
      if @_roleAccepted endpointContext, endpoint
        endpoint.action.call endpointContext
      else
        statusCode: 401
        body: {status: "error", message: "You do not have permission to do this."}
    else
      statusCode: 401
      body: {status: "error", message: "You must be logged in to do this."}


  ###
    Authenticate the given endpoint if required

    Once it's globally configured in the API, authentication can be required on an entire route or individual
    endpoints. If required on an entire endpoint, that serves as the default. If required in any individual endpoints, that
    will override the default.

    @returns False if authentication fails, and true otherwise
  ###
  _authAccepted: (endpointContext, endpoint) ->
    if endpoint.authRequired
      @_authenticate endpointContext
    else true


  ###
    Verify the request is being made by an actively logged in user

    If verified, attach the authenticated user to the context.

    @returns {Boolean} True if the authentication was successful
  ###
  _authenticate: (endpointContext) ->
    # Get auth info
    auth = @api.config.auth.user.call(endpointContext)

    # Get the user from the database
    if not auth?.user and auth?.userId and auth?.token
      userSelector = {}
      userSelector._id = auth.userId
      userSelector[@api.config.auth.token] = auth.token
      auth.user = Meteor.users.findOne userSelector

    # Attach the user and their ID to the context if the authentication was successful
    if auth?.user
      endpointContext.user = auth.user
      endpointContext.userId = auth.user._id
      true
    else false


  ###
    Authenticate the user role if required

    Must be called after _authAccepted().

    @returns True if the authenticated user belongs to <i>any</i> of the acceptable roles on the endpoint
  ###
  _roleAccepted: (endpointContext, endpoint) ->
    if endpoint.roleRequired
      if _.isEmpty _.intersection(endpoint.roleRequired, endpointContext.user.roles)
        return false
    true


  ###
    Respond to an HTTP request
  ###
  _respond: (endpointContext, body, statusCode=200, headers) ->
    # Allow cross-domain requests to be made from the browser
    endpointContext.response.setHeader 'Access-Control-Allow-Origin', '*'

    # Ensure that a content type is set (will be overridden if also included in given headers)
    # TODO: Consider enforcing a text/json-only content type (override any user-defined content-type)
    if headers == undefined
        headers = {'contenttype': 'text/json'}
    endpointContext.response.setHeader 'Content-Type', headers.contenttype
    
    if headers.contenttype == 'text/json'
        # Prettify JSON if configured in API
        if @api.config.prettyJson
           bodyAsJson = JSON.stringify body, undefined, 2
        else
           bodyAsJson = JSON.stringify body

        # Send response
        endpointContext.response.writeHead statusCode, headers
        endpointContext.response.write bodyAsJson
        endpointContext.response.end()
    else
        endpointContext.response.writeHead statusCode, headers
        endpointContext.response.write body
        endpointContext.response.end()
