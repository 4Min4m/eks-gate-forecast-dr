# These are exactly the values you paste into ../backend.hcl
output "state_bucket_name" {
  description = "S3 bucket for Terraform remote state"
  value       = aws_s3_bucket.state.id
}

output "lock_table_name" {
  description = "DynamoDB table for state locking"
  value       = aws_dynamodb_table.locks.name
}

output "region" {
  description = "Region of the state bucket / lock table"
  value       = var.region
}

output "backend_hcl_snippet" {
  description = "Copy this into ../backend.hcl"
  value       = <<-EOT
    bucket         = "${aws_s3_bucket.state.id}"
    region         = "${var.region}"
    dynamodb_table = "${aws_dynamodb_table.locks.name}"
  EOT
}
