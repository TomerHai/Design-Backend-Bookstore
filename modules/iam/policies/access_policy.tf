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
