# modules/cognito/cognito.tf

# Using Cognito
# Provision AWS Cognito user pool

resource "aws_cognito_user_pool" "pool" {
  name = "mypool"
}

# Adding a Cognito user pool client, so I could integrate this user pool with the API Gateway I've created
# I used this as reference (as this is my first pool configuration)
# https://docs.aws.amazon.com/cognito-user-identity-pools/latest/APIReference/API_InitiateAuth.html#API_InitiateAuth_RequestSyntax

resource "aws_cognito_user_pool_client" "api_client" {
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

output "user_pool_arn" {
  value = aws_cognito_user_pool.pool.arn
}