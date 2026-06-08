terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
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
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.url_checker.arn}:*",
          "${aws_cloudwatch_log_group.api_handler.arn}:*"
        ]
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

resource "aws_cloudwatch_log_group" "url_checker" {
  name              = "/aws/lambda/cloudops-url-checker"
  retention_in_days = 14

  tags = { Project = "cloudops-uptime-monitor" }
}

resource "aws_cloudwatch_log_group" "api_handler" {
  name              = "/aws/lambda/cloudops-api-handler"
  retention_in_days = 14

  tags = { Project = "cloudops-uptime-monitor" }
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
      AWS_REGION        = var.aws_region
      RESULT_TTL_DAYS   = tostring(var.result_ttl_days)
    }
  }

  depends_on = [aws_cloudwatch_log_group.url_checker]

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
      AWS_REGION        = var.aws_region
    }
  }

  depends_on = [aws_cloudwatch_log_group.api_handler]

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

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.uptime_api.id
  parent_id   = aws_api_gateway_rest_api.uptime_api.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy_any" {
  rest_api_id   = aws_api_gateway_rest_api.uptime_api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "proxy_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.uptime_api.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy_any.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_handler.invoke_arn
}

resource "aws_api_gateway_deployment" "uptime_api" {
  rest_api_id = aws_api_gateway_rest_api.uptime_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.proxy_any.id,
      aws_api_gateway_integration.proxy_lambda.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.uptime_api.id
  deployment_id = aws_api_gateway_deployment.uptime_api.id
  stage_name    = "prod"
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
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "cloudops-uptime-monitor-oac"
  description                       = "CloudFront access control for CloudOps Uptime Monitor frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "frontend-s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "frontend-s3-origin"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = { Project = "cloudops-uptime-monitor" }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudFrontRead"
      Effect = "Allow"
      Principal = {
        Service = "cloudfront.amazonaws.com"
      }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.frontend.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
        }
      }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

resource "aws_cloudwatch_metric_alarm" "url_checker_errors" {
  alarm_name          = "cloudops-url-checker-errors"
  alarm_description   = "URL checker Lambda reported at least one error"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.url_checker.function_name
  }

  alarm_actions = [aws_sns_topic.uptime_alerts.arn]

  tags = { Project = "cloudops-uptime-monitor" }
}

resource "aws_cloudwatch_metric_alarm" "url_checker_duration" {
  alarm_name          = "cloudops-url-checker-duration"
  alarm_description   = "URL checker Lambda average duration is near timeout"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = 25000
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.url_checker.function_name
  }

  alarm_actions = [aws_sns_topic.uptime_alerts.arn]

  tags = { Project = "cloudops-uptime-monitor" }
}

resource "aws_cloudwatch_metric_alarm" "api_handler_errors" {
  alarm_name          = "cloudops-api-handler-errors"
  alarm_description   = "API handler Lambda reported at least one error"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.api_handler.function_name
  }

  alarm_actions = [aws_sns_topic.uptime_alerts.arn]

  tags = { Project = "cloudops-uptime-monitor" }
}

resource "aws_cloudwatch_dashboard" "uptime_monitor" {
  dashboard_name = "CloudOps-Uptime-Monitor"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Lambda Errors"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", aws_lambda_function.url_checker.function_name],
            [".", ".", ".", aws_lambda_function.api_handler.function_name]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Lambda Duration"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.url_checker.function_name, { stat = "Average" }],
            [".", ".", ".", aws_lambda_function.api_handler.function_name, { stat = "Average" }]
          ]
        }
      }
    ]
  })
}
