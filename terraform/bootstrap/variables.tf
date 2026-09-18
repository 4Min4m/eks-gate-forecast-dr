variable "region" {
  description = "AWS region for the state bucket and lock table"
  type        = string
  default     = "us-east-1"
}

# S3 bucket names are GLOBALLY unique — no default on purpose.
variable "state_bucket_name" {
  description = "Globally-unique name for the Terraform state S3 bucket"
  type        = string
}

variable "lock_table_name" {
  description = "Name for the DynamoDB state-lock table"
  type        = string
  default     = "terraform-locks"
}

variable "noncurrent_version_expiration_days" {
  description = "Days after which old state versions are expired"
  type        = number
  default     = 90
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default = {
    Project   = "eks-httpbin-alb"
    ManagedBy = "terraform"
    Purpose   = "tf-remote-state"
  }
}
