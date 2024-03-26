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

# instead of hard coding the names in Lambda and Terraform, read them
# from the environment by creating entries in AWS Systems Manager Parameter Store.

resource "aws_ssm_parameter" "dynamodb_table_name" {
  name = "/app/bookstore/dynamodb_table_name"
  value = module.database.table_name  # Reference output from database module
  type = "String"
}
resource "aws_ssm_parameter" "s3_bucket_name" {
  name = "/app/bookstore/s3_bucket_name"
  value = aws_s3_bucket.mybucket.bucket  # Reference S3 bucket name
  type = "String"
}

# Set the DB
module "database" {
  source "./modules/database"
}

# Set the storage
module "storage" {
  source "./modules/storage"
}

# Set the IAM policy and role
module "iam" {
  source = "./modules/iam"
}

# Attach the policy to the IAM role (implicitly depends on IAM policy)
resource "aws_iam_role_policy_attachment" "lambda_invoke_attachment" {
  role       = aws_iam_role.IAM-Bookstore-task-role.name # referring to the local resource
  policy_arn = aws_iam_policy.IAM-Bookstore-task-policy.arn
}
 
# Set the Lambda function
module "lambda" {
  source = "./modules/lambda"
  depends_on = [module.iam]  # Explicitly declare dependency on the IAM module
}

# Set the Cognito
module "cognito" {
  source = "./modules/cognito"  
}

# Set the API Gateway module

module "api_gateway" {
  source = "./modules/api_gateway"
  depends_on =[module.cognito, module.lambda] # Explicitly declare dependencies on the Cognito and Lambda modules
}