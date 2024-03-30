# modules/lambda/lambda.tf module

variable "iam_role_arn" {
  type = string
  description = "The arn of the iam_role for lambda permissions"
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
  role          = var.iam_role_arn  # Use the output value of the iam_roles module
  handler       = "Lambda-bookstore-task.lambda_handler"  # Specify the Lambda function code
  runtime       = "python3.12"  # Choosing the python runtime
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
    # Advanced logging controls (optional)
  logging_config {
    log_format = "JSON"
  }
}
output "lambda_function_name" {
  value = aws_lambda_function.Lambda-bookstore-task.function_name
}
output "lambda_function_arn" {
  value = aws_lambda_function.Lambda-bookstore-task.arn
}
