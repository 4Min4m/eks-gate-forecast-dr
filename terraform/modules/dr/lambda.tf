data "archive_file" "dr_lambda" {
  count       = var.enable_dr_poc ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/lambda/handler.zip"
}

resource "aws_lambda_function" "dr_check_primary" {
  count            = var.enable_dr_poc ? 1 : 0
  function_name    = "${var.name_prefix}-dr-poc-primary"
  role             = aws_iam_role.dr_lambda[0].arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.dr_lambda[0].output_path
  source_code_hash = data.archive_file.dr_lambda[0].output_base64sha256
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.dr_state[0].name
    }
  }

  tags = var.tags
}

resource "aws_lambda_function" "dr_check_secondary" {
  count            = var.enable_dr_poc ? 1 : 0
  provider         = aws.secondary
  function_name    = "${var.name_prefix}-dr-poc-secondary"
  role             = aws_iam_role.dr_lambda[0].arn # IAM is global — same role, different region's Lambda
  handler          = "handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.dr_lambda[0].output_path
  source_code_hash = data.archive_file.dr_lambda[0].output_base64sha256
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.dr_state[0].name
    }
  }

  tags = var.tags
}
