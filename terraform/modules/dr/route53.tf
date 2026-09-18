locals {
  # API Gateway HTTP APIs expose a plain "<api-id>.execute-api.<region>.amazonaws.com"
  # domain with a valid AWS-managed cert — good enough for a health check
  # and a CNAME without needing a custom domain/ACM cert for this POC.
  primary_domain   = var.enable_dr_poc ? "${aws_apigatewayv2_api.dr_primary[0].id}.execute-api.${var.primary_region}.amazonaws.com" : ""
  secondary_domain = var.enable_dr_poc ? "${aws_apigatewayv2_api.dr_secondary[0].id}.execute-api.${var.secondary_region}.amazonaws.com" : ""

  create_dns_record = var.enable_dr_poc && var.hosted_zone_id != ""
}

resource "aws_route53_health_check" "primary" {
  count             = var.enable_dr_poc ? 1 : 0
  fqdn              = local.primary_domain
  port              = 443
  type              = "HTTPS"
  resource_path     = "/dr-check"
  failure_threshold = 3  # 3 consecutive failed checks...
  request_interval  = 10 # ...at 10s each = ~30s to detect. This IS your RTO
  # lower bound before DNS TTL/client caching are even considered — measure
  # and record the REAL end-to-end number in the Phase 4 exercise, don't
  # just quote this config value.
  tags = merge(var.tags, { Name = "${var.name_prefix}-dr-poc-primary-health" })
}

resource "aws_route53_health_check" "secondary" {
  count             = var.enable_dr_poc ? 1 : 0
  fqdn              = local.secondary_domain
  port              = 443
  type              = "HTTPS"
  resource_path     = "/dr-check"
  failure_threshold = 3
  request_interval  = 10
  tags              = merge(var.tags, { Name = "${var.name_prefix}-dr-poc-secondary-health" })
}

resource "aws_route53_record" "primary" {
  count           = local.create_dns_record ? 1 : 0
  zone_id         = var.hosted_zone_id
  name            = var.record_name
  type            = "CNAME"
  ttl             = 30 # short TTL on purpose — this is the other half of your real RTO number
  records         = [local.primary_domain]
  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary[0].id

  failover_routing_policy {
    type = "PRIMARY"
  }
}

resource "aws_route53_record" "secondary" {
  count           = local.create_dns_record ? 1 : 0
  zone_id         = var.hosted_zone_id
  name            = var.record_name
  type            = "CNAME"
  ttl             = 30
  records         = [local.secondary_domain]
  set_identifier  = "secondary"
  health_check_id = aws_route53_health_check.secondary[0].id

  failover_routing_policy {
    type = "SECONDARY"
  }
}
