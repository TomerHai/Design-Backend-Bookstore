# modules/iam_policy/iam_policy.tf

# Creating an IAM policy and role for Lambda functions
# I used ${var.aws_region} and ${var.aws_account_id} to dynamically insert the region and account ID into the resource ARNs.
# This ensures the policy adapts to the environment where Terraform is deployed.

variable "aws_region" {
  type = string
  description = "AWS region where resources are deployed"
}

variable "aws_account_id" {
  type = string
  description = "AWS account ID of the user deploying resources"
}

variable "dynamo_table_name" {
  type = string
  description = "The name of the DynamoDB table"
}

variable "lambda_function_name" {
  type = string
  description = "The name of the Lambda function"
}

variable "lambda_function_arn" {
  type = string
  description = "The arn address of the Lambda function"
}

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
             "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/${var.dynamo_table_name}"
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
            "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/lambda/${var.lambda_function_name}:*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "lambda:InvokeFunction",
            "Resource": [
            "${var.lambda_function_arn}"
            ]
        }
    ]
}
EOF
}

output "iam_policy_arn" {
  value = aws_iam_policy.IAM-Bookstore-task-policy.arn
}