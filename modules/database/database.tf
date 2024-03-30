# modules/database/database.tf
# Creating a DynamoDB table for book inventory

resource "aws_dynamodb_table" "bookstore" {
  name         = "bookstore"
  billing_mode   = "PAY_PER_REQUEST"  # Serverless mode
  hash_key       = "ISBN"
  attribute {
    name = "ISBN"
    type = "S"  # String type
  }
}

output "table_name" {
  value = aws_dynamodb_table.bookstore.name
}