data "aws_caller_identity" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  oidc_sub    = replace(var.oidc_issuer_url, "https://", "")
}
