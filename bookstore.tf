# Define variables for the AWS provider and access
# For this task, the process assumes we deploy using terraform with variables to hold the access/secret keys used to perform this task

variable "aws_region" {
  type = string
  description = "The region in which the resources will be created"
  default = "il-central-1"
}

variable "access_key" {
  type = string
  description = "The aws development account access key"
}

variable "secret_key" {
  type = string
  description = "The aws development account secret key"
}

# Add a data source to retrieve the information of the current caller's identity, included the account ID.
data "aws_caller_identity" "current" {}

// Providers
provider "aws" {
  region     = var.aws_region
  access_key = var.access_key
  secret_key = var.secret_key
}
 

# Creating a DynamoDB table for book inventory

resource "aws_dynamodb_table" "bookstore" {
  name           = "bookstore"
  billing_mode   = "PAY_PER_REQUEST"  # Serverless mode
  hash_key       = "ISBN"
  attribute {
    name = "ISBN"
    type = "S"  # String type
  }
}

# Creating the S3 Bucket (bookstore-task-images) for storing the book images. Simple S3 with no versioning.
resource "aws_s3_bucket" "mybucket" {
  bucket = "bookstore-task-images"
}

# Creating an IAM policy and role for Lambda functions
# I used ${var.aws_region} and ${aws_caller_identity.current.account_id} to dynamically insert the region and account ID into the resource ARNs.
# This ensures the policy adapts to the environment where Terraform is deployed.

resource "aws_iam_policy" "IAM-Bookstore-task-policy" {
  name        = "IAM-Bookstore-task-policy"
  path        = "/"
  description = "IAM-Bookstore-task-policy"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:DeleteItem",
                "dynamodb:UpdateItem",
                "dynamodb:Scan",
                "dynamodb:Query"
            ],
            "Resource": [
             "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${aws_dynamodb_table.bookstore.name}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Resource": [
            "arn:aws:s3:::bookstore-task-images/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": [
            "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/Lambda-bookstore-task:*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "lambda:InvokeFunction",
            "Resource": [
            "${aws_lambda_function.Lambda-bookstore-task.arn}"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_role" "IAM-Bookstore-task-role" {
  name = "IAM-Bookstore-task-role"
  assume_role_policy = jsonencode(
  {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
  })
}

  # Attach the policy to the IAM role (implicitly depends on IAM policy)
resource "aws_iam_role_policy_attachment" "lambda_invoke_attachment" {
  role       = aws_iam_role.IAM-Bookstore-task-role.name
  policy_arn = aws_iam_policy.IAM-Bookstore-task-policy.arn
}
 

# create the data source for the Lambda
data "archive_file" "lambda_package" {
  type = "zip"
  source_file = "Lambda-bookstore-task.py"
  output_path = "lambda-function.zip"
}
# define the retention policy for the logs created for Lambda inside CloudWatch
resource "aws_cloudwatch_log_group" "lambda_logs" {
    name = "/aws/lambda/Lambda-bookstore-task"
    retention_in_days = 7
}

# Create a Lambda function for the bookstore management using CRUD actions

resource "aws_lambda_function" "Lambda-bookstore-task" {
  filename      = "lambda-function.zip"
  function_name = "Lambda-bookstore-task"
  role          = aws_iam_role.IAM-Bookstore-task-role.arn
  handler       = "Lambda-bookstore-task.lambda_handler"  # Specify the Lambda function code
  runtime       = "python3.12"  # Choosing the python runtime
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
    # Advanced logging controls (optional)
  logging_config {
    log_format = "JSON"
  }
}

# Using Cognito: This section comes before the API GW section due to dependencies (as the API GW will use the Cognito as authorizer for access)
# Provision AWS Cognito user pool

resource "aws_cognito_user_pool" "pool" {
  name = "mypool"
}

# Adding a Cognito user pool client, so I could integrate this user pool with the API Gateway I've created
# I used this as reference (as this is my first pool configuration)
# https://docs.aws.amazon.com/cognito-user-identity-pools/latest/APIReference/API_InitiateAuth.html#API_InitiateAuth_RequestSyntax

resource "aws_cognito_user_pool_client" "client" {
  name = "client"
  allowed_oauth_flows_user_pool_client = true
  generate_secret = false
  # providing the authentication methods allowed to this client 
  allowed_oauth_scopes = ["aws.cognito.signin.user.admin","email", "openid", "profile"]
  allowed_oauth_flows = ["implicit", "code"]
  explicit_auth_flows = ["ADMIN_NO_SRP_AUTH", "USER_PASSWORD_AUTH"]
  supported_identity_providers = ["COGNITO"]

  user_pool_id = aws_cognito_user_pool.pool.id # this associate the Cognito user pool to this client
  callback_urls = ["https://www.google.com"] # the URL to which the user will be redirected post successful authentication
}
# add a test user for testing the access to the API. It will be removed if all OK (not to be use in production)
resource "aws_cognito_user" "example" {
  user_pool_id = aws_cognito_user_pool.pool.id
  username = "tomer"
  password = "Test@123"
}

# Add Cognito Authorizer in the API GW for authorization
# when the authorizer is enables, any incoming request token is first validated against this Cognito user pool before Lambda is triggered
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
    name = "cognito_authorizer" # providing a name to the authorizer
    rest_api_id = aws_api_gateway_rest_api.BookstoreOperations.id # associate it with the REST API I built
    type = "COGNITO_USER_POOLS"  # Use Cognito user pool for authorization this should match the authorization tag I've placed on the aws_api_gateway_method resource
    provider_arns = [aws_cognito_user_pool.pool.arn]  # Reference to the user pool in which the validated users reside
}

# Create an API Gateway

resource "aws_api_gateway_rest_api" "BookstoreOperations" {
  name = "BookstoreOperations"
  endpoint_configuration {
  types = ["REGIONAL"]
  }
}

# Create a resource 

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

  uri = "${aws_lambda_function.Lambda-bookstore-task.invoke_arn}"
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
  statement_id = "allow-api-gateway-invoke-${aws_lambda_function.Lambda-bookstore-task.function_name}"
  principal = "apigateway.amazonaws.com"  # Define the principal to work with
  action = "lambda:InvokeFunction"
  function_name = aws_lambda_function.Lambda-bookstore-task.arn
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