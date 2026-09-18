# Remote state — one state file per environment (partial config in backend.hcl).
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {
    key     = "eks-httpbin-alb/dev/terraform.tfstate"
    encrypt = true
  }
}
