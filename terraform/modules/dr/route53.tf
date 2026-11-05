locals {
  # Each region's default "<api-id>.execute-api.<region>.amazonaws.com" domain.
  # The health checks target these directly so each region's health is judged
  # on its own, independent of DNS.
  primary_domain   = var.enable_dr_poc ? "${aws_apigatewayv2_api.dr_primary[0].id}.execute-api.${var.primary_region}.amazonaws.com" : ""
  secondary_domain = var.enable_dr_poc ? "${aws_apigatewayv2_api.dr_secondary[0].id}.execute-api.${var.secondary_region}.amazonaws.com" : ""

  create_dns_record = var.enable_dr_poc && var.hosted_zone_id != ""

  # dr-poc.example.com
  failover_fqdn = local.create_dns_record ? "${var.record_name}.${trimsuffix(data.aws_route53_zone.this[0].name, ".")}" : ""
}

data "aws_route53_zone" "this" {
  count   = local.create_dns_record ? 1 : 0
  zone_id = var.hosted_zone_id
}

# ---------------------------------------------------------------------------
# Health checks — one per region, straight at the default execute-api domain.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Custom domain in BOTH regions.
#
# Why this is needed: a plain CNAME from dr-poc.example.com to an
# execute-api domain does not work. The client would send
# Host: dr-poc.example.com, which API Gateway rejects (403), and the TLS
# certificate presented is *.execute-api..., which doesn't match the name
# the client asked for. So each region gets an API Gateway custom domain for
# the same name, with its own regional ACM certificate, and Route 53 failover
# aliases point at those.
# ---------------------------------------------------------------------------
resource "aws_acm_certificate" "primary" {
  count             = local.create_dns_record ? 1 : 0
  domain_name       = local.failover_fqdn
  validation_method = "DNS"
  tags              = var.tags
  lifecycle { create_before_destroy = true }
}

resource "aws_acm_certificate" "secondary" {
  count             = local.create_dns_record ? 1 : 0
  provider          = aws.secondary
  domain_name       = local.failover_fqdn
  validation_method = "DNS"
  tags              = var.tags
  lifecycle { create_before_destroy = true }
}

# ACM issues the same validation record for the same name in every region of
# an account, so one record (allow_overwrite) validates both certificates.
resource "aws_route53_record" "cert_validation" {
  count           = local.create_dns_record ? 1 : 0
  zone_id         = var.hosted_zone_id
  name            = tolist(aws_acm_certificate.primary[0].domain_validation_options)[0].resource_record_name
  type            = tolist(aws_acm_certificate.primary[0].domain_validation_options)[0].resource_record_type
  records         = [tolist(aws_acm_certificate.primary[0].domain_validation_options)[0].resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "primary" {
  count                   = local.create_dns_record ? 1 : 0
  certificate_arn         = aws_acm_certificate.primary[0].arn
  validation_record_fqdns = [aws_route53_record.cert_validation[0].fqdn]
}

resource "aws_acm_certificate_validation" "secondary" {
  count                   = local.create_dns_record ? 1 : 0
  provider                = aws.secondary
  certificate_arn         = aws_acm_certificate.secondary[0].arn
  validation_record_fqdns = [aws_route53_record.cert_validation[0].fqdn]
}

resource "aws_apigatewayv2_domain_name" "primary" {
  count       = local.create_dns_record ? 1 : 0
  domain_name = local.failover_fqdn
  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.primary[0].certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
  tags = var.tags
}

resource "aws_apigatewayv2_domain_name" "secondary" {
  count       = local.create_dns_record ? 1 : 0
  provider    = aws.secondary
  domain_name = local.failover_fqdn
  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.secondary[0].certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
  tags = var.tags
}

resource "aws_apigatewayv2_api_mapping" "primary" {
  count       = local.create_dns_record ? 1 : 0
  api_id      = aws_apigatewayv2_api.dr_primary[0].id
  domain_name = aws_apigatewayv2_domain_name.primary[0].id
  stage       = aws_apigatewayv2_stage.dr_primary[0].id
}

resource "aws_apigatewayv2_api_mapping" "secondary" {
  count       = local.create_dns_record ? 1 : 0
  provider    = aws.secondary
  api_id      = aws_apigatewayv2_api.dr_secondary[0].id
  domain_name = aws_apigatewayv2_domain_name.secondary[0].id
  stage       = aws_apigatewayv2_stage.dr_secondary[0].id
}

# ---------------------------------------------------------------------------
# Failover records — CNAMEs to each region's custom-domain target. (Now that
# the name matches a custom domain + certificate in each region, a CNAME is
# fine; a CNAME rather than an alias also lets us set the short TTL.)
# ---------------------------------------------------------------------------
resource "aws_route53_record" "primary" {
  count           = local.create_dns_record ? 1 : 0
  zone_id         = var.hosted_zone_id
  name            = local.failover_fqdn
  type            = "CNAME"
  ttl             = 30 # short on purpose — the other half of your real RTO number
  records         = [aws_apigatewayv2_domain_name.primary[0].domain_name_configuration[0].target_domain_name]
  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary[0].id

  failover_routing_policy {
    type = "PRIMARY"
  }
}

resource "aws_route53_record" "secondary" {
  count           = local.create_dns_record ? 1 : 0
  zone_id         = var.hosted_zone_id
  name            = local.failover_fqdn
  type            = "CNAME"
  ttl             = 30 # short on purpose — the other half of your real RTO number
  records         = [aws_apigatewayv2_domain_name.secondary[0].domain_name_configuration[0].target_domain_name]
  set_identifier  = "secondary"
  health_check_id = aws_route53_health_check.secondary[0].id

  failover_routing_policy {
    type = "SECONDARY"
  }
}
