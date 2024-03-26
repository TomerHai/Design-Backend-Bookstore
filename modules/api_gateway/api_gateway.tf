# api_gateway/api_gateway.tf

# Create an API Gateway

resource "aws_api_gateway_rest_api" "BookstoreOperations" {
  name = "BookstoreOperations"
  endpoint_configuration {
  types = ["REGIONAL"]
  }
}

# Create the resource 

resource "aws_api_gateway_resource" "root" {
  rest_api_id = aws_api_gateway_rest_api.BookstoreOperations.id
  parent_id   = aws_api_gateway_rest_api.BookstoreOperations.root_resource_id
  path_part   = "bookstore"
}

# Create the Method. Every API Gateway resource consists of four components: 
# Method request, Integration Request, Integration Response, and Method Response. 
# These components are responsible for processing incoming requests and outgoing responses in various ways.

resource "aws_api_gateway_method" "BookstoreManager" {
  rest_api_id = aws_api_gateway_rest_api.BookstoreOperations.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = "POST"
  authorization = "COGNITO_USER_POOLS"  # Set authorization type based on Cognito user_pool defined above
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id  # the name of the aws_api_gateway_authorizer defined in the Cognito section
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.BookstoreOperations.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = aws_api_gateway_method.BookstoreManager.http_method
  integration_http_method = "POST"
  # Building the uri argument as reference to the invoke_arn attribute of the Lambda function resource I created above
  # I used the type "AWS" here as uri requires it and the value "AWS" means to bypass the proxy integration setting (while AWS_PROXY means to use the proxy setting)
  # NOTE that I have a problem as my Lambda function requires passing that Lambda Proxy Integration will be set to False, still, if I use type=AWS, it will be set to false
  # and I will need to manuall switch it to true and then back to false on the console to make it work (which means the console does additional task when changing the proxy value
  # and I miss it here in the terraform.

  uri = "${module.aws_lambda_function.Lambda-bookstore-task.invoke_arn}"
  type = "AWS"
  passthrough_behavior    = "WHEN_NO_MATCH"  # Explicitly disable proxy
}

resource "aws_api_gateway_method_response" "BookstoreManager" {
  rest_api_id = aws_api_gateway_rest_api.BookstoreOperations.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = aws_api_gateway_method.BookstoreManager.http_method
  status_code = "200"
}
resource "aws_api_gateway_integration_response" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.BookstoreOperations.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = aws_api_gateway_method.BookstoreManager.http_method
  status_code = aws_api_gateway_method_response.BookstoreManager.status_code

  depends_on = [
    aws_api_gateway_method.BookstoreManager,
    aws_api_gateway_integration.lambda_integration
  ]
}

# This section was added later, when I discovered that there is a need to add a specific resource-based policies on the Lambda functions
# to allow the invocation of the Lambda correctly by the API Gateway. 
# This was discovered by chance, by tracking what does switching of the "Lambda Proxy Integration" button from False/True to True/False does.
# this setting is on the Integration Request section of the API Gateway method.
# Once I've discovered it adds a resource-based policy to the Lambda, it was easy to replicate it here correctly, which is what the resource below does.

resource "aws_lambda_permission" "allow_api_gateway_to_invoke" {
  statement_id = "allow-api-gateway-invoke-${module.aws_lambda_function.Lambda-bookstore-task.function_name}"
  principal = "apigateway.amazonaws.com"  # Define the principal to work with
  action = "lambda:InvokeFunction"
  function_name = module.aws_lambda_function.Lambda-bookstore-task.arn
  source_arn = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*/*/POST/bookstore"
  depends_on = [  # this assumes the method is created first (see above)
    aws_api_gateway_method.BookstoreManager
  ] 
}

# Deploy the API into a single environment for the sake of the task
# no stage_name is required. In real environment, additional environments (dev/test/etc.) can be set
# Deployement can be done only once the Rest API method is set.

resource "aws_api_gateway_deployment" "bookstore_deployment" {
  rest_api_id = aws_api_gateway_rest_api.BookstoreOperations.id
  depends_on = [
    aws_api_gateway_method.BookstoreManager,
    aws_api_gateway_integration.lambda_integration
  ]
}

# Add Cognito Authorizer in the API GW for authorization
# when the authorizer is enables, any incoming request token is first validated against this Cognito user pool before Lambda is triggered
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
    name = "cognito_authorizer" # providing a name to the authorizer
    rest_api_id = aws_api_gateway_rest_api.BookstoreOperations.id # associate it with the REST API I built
    type = "COGNITO_USER_POOLS"  # Use Cognito user pool for authorization this should match the authorization tag I've placed on the aws_api_gateway_method resource
    provider_arns = [module.cognito.aws_cognito_user_pool.pool.arn]  # Reference to the user pool from the Cognito module in which the validated users reside
}
