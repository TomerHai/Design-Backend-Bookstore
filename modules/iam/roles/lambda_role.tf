# lambda/lambda_role.tf
# Creating the relevant role for allowing Lambda to access the bookstore DB

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
