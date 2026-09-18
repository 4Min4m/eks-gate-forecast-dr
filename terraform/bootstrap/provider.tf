# Bootstrap stack: creates the S3 bucket + DynamoDB table that the MAIN stack
# uses for remote state. This stack itself uses LOCAL state (the classic
# chicken-and-egg): it's tiny, rarely changes, and can be committed as-is or
# kept out of VCS. Run it ONCE, before the main stack's `terraform init`.
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = var.tags
  }
}
