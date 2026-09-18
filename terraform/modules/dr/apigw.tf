# API Gateway HTTP API — cheaper and simpler than an ALB for a single
# Lambda-backed path, and (unlike an ALB) needs no VPC/subnets, which keeps
# the secondary region's footprint to just these few serverless resources.
locals {
  dr_routes = ["GET /dr-check", "POST /dr-check"]
}

# Primary region
resource "aws_apigatewayv2_api" "dr_primary" {
  count         = var.enable_dr_poc ? 1 : 0
  name          = "${var.name_prefix}-dr-poc-primary"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "dr_primary" {
  count                  = var.enable_dr_poc ? 1 : 0
  api_id                 = aws_apigatewayv2_api.dr_primary[0].id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.dr_check_primary[0].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "dr_primary" {
  for_each  = var.enable_dr_poc ? toset(local.dr_routes) : toset([])
  api_id    = aws_apigatewayv2_api.dr_primary[0].id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.dr_primary[0].id}"
}

resource "aws_apigatewayv2_stage" "dr_primary" {
  count       = var.enable_dr_poc ? 1 : 0
  api_id      = aws_apigatewayv2_api.dr_primary[0].id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "dr_primary" {
  count         = var.enable_dr_poc ? 1 : 0
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dr_check_primary[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.dr_primary[0].execution_arn}/*/*"
}

# Secondary region
resource "aws_apigatewayv2_api" "dr_secondary" {
  count         = var.enable_dr_poc ? 1 : 0
  provider      = aws.secondary
  name          = "${var.name_prefix}-dr-poc-secondary"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "dr_secondary" {
  count                  = var.enable_dr_poc ? 1 : 0
  provider               = aws.secondary
  api_id                 = aws_apigatewayv2_api.dr_secondary[0].id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.dr_check_secondary[0].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "dr_secondary" {
  for_each  = var.enable_dr_poc ? toset(local.dr_routes) : toset([])
  provider  = aws.secondary
  api_id    = aws_apigatewayv2_api.dr_secondary[0].id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.dr_secondary[0].id}"
}

resource "aws_apigatewayv2_stage" "dr_secondary" {
  count       = var.enable_dr_poc ? 1 : 0
  provider    = aws.secondary
  api_id      = aws_apigatewayv2_api.dr_secondary[0].id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "dr_secondary" {
  count         = var.enable_dr_poc ? 1 : 0
  provider      = aws.secondary
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dr_check_secondary[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.dr_secondary[0].execution_arn}/*/*"
}
