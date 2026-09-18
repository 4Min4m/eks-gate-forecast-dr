resource "aws_dynamodb_table" "dr_state" {
  count        = var.enable_dr_poc ? 1 : 0
  name         = "${var.name_prefix}-dr-poc-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  replica {
    region_name = var.secondary_region
  }

  tags = merge(var.tags, { Purpose = "dr-poc" })
}

# One IAM role, used by BOTH regions' Lambda functions — IAM is a global
# service, so this doesn't need to exist per-region the way Lambda/API
# Gateway do. Scoped to exactly this table (and its replica) plus basic
# Lambda logging, nothing else.
data "aws_caller_identity" "current" {}

resource "aws_iam_role" "dr_lambda" {
  count = var.enable_dr_poc ? 1 : 0
  name  = "${var.name_prefix}-dr-poc-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "dr_lambda" {
  count = var.enable_dr_poc ? 1 : 0
  name  = "${var.name_prefix}-dr-poc-lambda-policy"
  role  = aws_iam_role.dr_lambda[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBReadWrite"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
        ]
        # Wildcard region/account suffix: the table name is the same in
        # both regions (that's how Global Tables work), only the region
        # segment of the ARN differs between the primary and replica.
        Resource = "arn:aws:dynamodb:*:${data.aws_caller_identity.current.account_id}:table/${var.name_prefix}-dr-poc-state"
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.name_prefix}-dr-poc-*"
      },
    ]
  })
}
