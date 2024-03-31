# modules/iam_policies/ssm_permissions.tf

# Using ${var.aws_region} and ${var.aws_account_id} to dynamically insert the region and account ID into the resource ARNs.
# This ensures the policy adapts to the environment where Terraform is deployed.

variable "aws_region" {
  type = string
  description = "AWS region where resources are deployed"
}

variable "aws_account_id" {
  type = string
  description = "AWS account ID of the user deploying resources"
}

# a dedicated policy to allow Lambda to read values from the SSM parameter store.

resource "aws_iam_policy" "lambda_ssm_permissions" {
  name = "lambda_ssm_permissions"
  policy = jsonencode(
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": "ssm:GetParameter",
          "Resource": [
            "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/app/bookstore/*"
          ]
        }
      ]
    }
  )
}

resource "aws_iam_role_policy_attachment" "attach_ssm_permissions" {
  role       = aws_iam_role.IAM-Bookstore-task-role.name
  policy_arn = aws_iam_policy.lambda_ssm_permissions.arn
}
