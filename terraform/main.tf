terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# DynamoDB — uptime checks
resource "aws_dynamodb_table" "uptime_checks" {
  name         = "uptime-checks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "url"
  range_key    = "timestamp"

  attribute {
    name = "url"
    type = "S"
  }
  attribute {
    name = "timestamp"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = { Project = "cloudops-uptime-monitor" }
}

# DynamoDB — monitored urls
resource "aws_dynamodb_table" "monitored_urls" {
  name         = "monitored-urls"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "url"

  attribute {
    name = "url"
    type = "S"
  }

  tags = { Project = "cloudops-uptime-monitor" }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "cloudops-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Least-privilege inline policy — replaces broad managed policies
resource "aws_iam_role_policy" "lambda_least_privilege" {
  name = "cloudops-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:DeleteItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.uptime_checks.arn,
          aws_dynamodb_table.monitored_urls.arn
        ]
      },
      {
        Sid      = "SNSPublish"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.uptime_alerts.arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# SNS Topic
resource "aws_sns_topic" "uptime_alerts" {
  name = "cloudops-uptime-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.uptime_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Lambda — URL Checker
data "archive_file" "url_checker_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/url_checker.py"
  output_path = "${path.module}/../lambda/url_checker.zip"
}

resource "aws_lambda_function" "url_checker" {
  filename         = data.archive_file.url_checker_zip.output_path
  function_name    = "cloudops-url-checker"
  role             = aws_iam_role.lambda_role.arn
  handler          = "url_checker.lambda_handler"
  runtime          = "python3.11"
  timeout          = 30
  memory_size      = 256
  source_code_hash = data.archive_file.url_checker_zip.output_base64sha256

  environment {
    variables = {
      CHECKS_TABLE_NAME = aws_dynamodb_table.uptime_checks.name
      URLS_TABLE_NAME   = aws_dynamodb_table.monitored_urls.name
      SNS_TOPIC_ARN     = aws_sns_topic.uptime_alerts.arn
    }
  }

  tags = { Project = "cloudops-uptime-monitor" }
}

# Lambda — API Handler
data "archive_file" "api_handler_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/api_handler.py"
  output_path = "${path.module}/../lambda/api_handler.zip"
}

resource "aws_lambda_function" "api_handler" {
  filename         = data.archive_file.api_handler_zip.output_path
  function_name    = "cloudops-api-handler"
  role             = aws_iam_role.lambda_role.arn
  handler          = "api_handler.lambda_handler"
  runtime          = "python3.11"
  timeout          = 30
  memory_size      = 256
  source_code_hash = data.archive_file.api_handler_zip.output_base64sha256

  environment {
    variables = {
      CHECKS_TABLE_NAME = aws_dynamodb_table.uptime_checks.name
      URLS_TABLE_NAME   = aws_dynamodb_table.monitored_urls.name
    }
  }

  tags = { Project = "cloudops-uptime-monitor" }
}

# EventBridge Schedule
resource "aws_cloudwatch_event_rule" "uptime_schedule" {
  name                = "cloudops-uptime-schedule"
  schedule_expression = "rate(5 minutes)"
  state               = "ENABLED"
}

resource "aws_cloudwatch_event_target" "url_checker_target" {
  rule      = aws_cloudwatch_event_rule.uptime_schedule.name
  arn       = aws_lambda_function.url_checker.arn
  target_id = "cloudops-url-checker"
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "cloudops-eventbridge-permission"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.url_checker.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.uptime_schedule.arn
}

# API Gateway
resource "aws_api_gateway_rest_api" "uptime_api" {
  name        = "cloudops-uptime-api"
  description = "CloudOps Uptime Monitor API"
}

resource "aws_lambda_permission" "apigateway" {
  statement_id  = "apigateway-invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.uptime_api.execution_arn}/*"
}

# S3 Bucket
resource "aws_s3_bucket" "frontend" {
  bucket = var.s3_bucket_name
  tags   = { Project = "cloudops-uptime-monitor" }
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  index_document { suffix = "index.html" }
  error_document { key = "index.html" }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = false
  ignore_public_acls      = false
  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadGetObject"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.frontend]
}
