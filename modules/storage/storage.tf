# modules/storage/storage.tf

# Creates an S3 bucket named "bookstore-task-images" to store book images.
# This bucket uses the default object ownership (bucket owner) and does not 
# have versioning enabled.

resource "aws_s3_bucket" "book_images" {
  bucket = "bookstore-task-images"
}

output "storage_name" {
  value = aws_s3_bucket.book_images.bucket
}