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

# Add a data source to retrieve the information of the current caller's identity, included the account ID. Define it as avariable to pass to needed modules

variable "aws_account_id" {
  type = string
  description = "The AWS account ID"
}
data "aws_caller_identity" "current" {}

# Assign the retrieved account ID to the variable
output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

// Providers
provider "aws" {
  region     = var.aws_region
  access_key = var.access_key
  secret_key = var.secret_key
}

# Set the DB
module "database" {
  source = "./modules/database"
}

# Set the storage
module "storage" {
  source = "./modules/storage"
}

# instead of hard coding the names in Lambda and Terraform, read them
# from the environment by creating entries in AWS Systems Manager Parameter Store.
resource "aws_ssm_parameter" "dynamodb_table_name" {
  name = "/app/bookstore/dynamodb_table_name"
  value = module.database.table_name  # Reference output from database module
  type = "String"
}
resource "aws_ssm_parameter" "s3_bucket_name" {
  name = "/app/bookstore/s3_bucket_name"
  value = module.storage.storage_name  # Reference S3 bucket name inside the storage module
  type = "String"
}

# Set the IAM roles
module "iam_roles" {
  source = "./modules/iam_roles"
}

# Set the Lambda function
module "lambda" {
  source = "./modules/lambda"
  depends_on = [module.iam_roles]  # Explicitly declare dependency on the IAM module
  iam_role_arn = module.iam_roles.iam_roles
}
# Set the IAM policy
module "iam_policy" {
  source = "./modules/iam_policy"
  # pass the required variables
  aws_region  = var.aws_region
  aws_account_id = var.aws_account_id
  dynamo_table_name = module.database.table_name
  lambda_function_name = module.lambda.lambda_function_name
  lambda_function_arn = module.lambda.lambda_function_arn
}

# Attach the policy to the IAM role (implicitly depends on IAM policy)
resource "aws_iam_role_policy_attachment" "lambda_invoke_attachment" {
  role       = module.iam_roles.iam_roles  # referring to the local resource
  policy_arn = module.iam_policy.iam_policy_arn.value
}
 
# Set the Cognito
module "cognito" {
  source = "./modules/cognito"  
}

# Assign the user pool ARN from the `cognito` module's output
variable "cognito_user_pool_arn" {
  type = string
  description = "ARN of the Cognito user pool"
}

# Set the API Gateway module and use the variable of the cognito pool we took as input for the api_gateway

module "api_gateway" {
  source = "./modules/api_gateway"
  cognito_user_pool_arn = var.cognito_user_pool_arn
  depends_on =[module.cognito, module.lambda] # Explicitly declare dependencies on the Cognito and Lambda modules
  aws_region = var.aws_region
  aws_account_id = var.aws_account_id
}