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

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  metric_namespace     = "CloudOps/UptimeMonitor"
  cors_allowed_origins = length(var.allowed_cors_origins) > 0 ? var.allowed_cors_origins : ["https://${aws_cloudfront_distribution.frontend.domain_name}"]
  primary_cors_origin  = local.cors_allowed_origins[0]
}

resource "aws_kms_key" "uptime_monitor" {
  description             = "Customer managed key for CloudOps Uptime Monitor data encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountAdministration"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogsUse"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = [
              "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/cloudops-*",
              "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/apigateway/cloudops-*"
            ]
          }
        }
      }
    ]
  })

  tags = { Project = "cloudops-uptime-monitor" }
}

resource "aws_kms_alias" "uptime_monitor" {
  name          = "alias/cloudops-uptime-monitor"
  target_key_id = aws_kms_key.uptime_monitor.key_id
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

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.uptime_monitor.arn
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

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.uptime_monitor.arn
  }

  tags = { Project = "cloudops-uptime-monitor" }
}

# DynamoDB — latest status lookup
resource "aws_dynamodb_table" "latest_status" {
  name         = "latest-url-status"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "url"

  attribute {
    name = "url"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.uptime_monitor.arn
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
          aws_dynamodb_table.monitored_urls.arn,
          aws_dynamodb_table.latest_status.arn
        ]
      },
      {
        Sid      = "CloudWatchMetrics"
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = local.metric_namespace
          }
        }
      },
      {
        Sid      = "SNSPublish"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.uptime_alerts.arn
      },
      {
        Sid    = "KMSUse"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.uptime_monitor.arn
      },
      {
        Sid    = "DeadLetterQueueWrite"
        Effect = "Allow"
        Action = ["sqs:SendMessage"]
        Resource = [
          aws_sqs_queue.url_checker_dlq.arn,
          aws_sqs_queue.api_handler_dlq.arn
        ]
      },
      {
        Sid    = "XRayWrite"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
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
  name              = "cloudops-uptime-alerts"
  kms_master_key_id = aws_kms_key.uptime_monitor.arn
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.uptime_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_log_group" "url_checker" {
  name              = "/aws/lambda/cloudops-url-checker"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.uptime_monitor.arn

  tags = { Project = "cloudops-uptime-monitor" }
}

resource "aws_cloudwatch_log_group" "api_handler" {
  name              = "/aws/lambda/cloudops-api-handler"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.uptime_monitor.arn

  tags = { Project = "cloudops-uptime-monitor" }
}

resource "aws_sqs_queue" "url_checker_dlq" {
  name                      = "cloudops-url-checker-dlq"
  message_retention_seconds = 1209600
  kms_master_key_id         = aws_kms_key.uptime_monitor.arn

  tags = { Project = "cloudops-uptime-monitor" }
}

resource "aws_sqs_queue" "api_handler_dlq" {
  name                      = "cloudops-api-handler-dlq"
  message_retention_seconds = 1209600
  kms_master_key_id         = aws_kms_key.uptime_monitor.arn

  tags = { Project = "cloudops-uptime-monitor" }
}

# Lambda — URL Checker
data "archive_file" "url_checker_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/url_checker.py"
  output_path = "${path.module}/../lambda/url_checker.zip"
}

resource "aws_lambda_function" "url_checker" {
  filename                       = data.archive_file.url_checker_zip.output_path
  function_name                  = "cloudops-url-checker"
  role                           = aws_iam_role.lambda_role.arn
  handler                        = "url_checker.lambda_handler"
  runtime                        = "python3.11"
  timeout                        = 30
  memory_size                    = 256
  kms_key_arn                    = aws_kms_key.uptime_monitor.arn
  reserved_concurrent_executions = 5
  source_code_hash               = data.archive_file.url_checker_zip.output_base64sha256

  environment {
    variables = {
      CHECKS_TABLE_NAME        = aws_dynamodb_table.uptime_checks.name
      URLS_TABLE_NAME          = aws_dynamodb_table.monitored_urls.name
      LATEST_STATUS_TABLE_NAME = aws_dynamodb_table.latest_status.name
      SNS_TOPIC_ARN            = aws_sns_topic.uptime_alerts.arn
      AWS_REGION               = var.aws_region
      RESULT_TTL_DAYS          = tostring(var.result_ttl_days)
      METRIC_NAMESPACE         = local.metric_namespace
    }
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.url_checker_dlq.arn
  }

  tracing_config {
    mode = "Active"
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
  filename                       = data.archive_file.api_handler_zip.output_path
  function_name                  = "cloudops-api-handler"
  role                           = aws_iam_role.lambda_role.arn
  handler                        = "api_handler.lambda_handler"
  runtime                        = "python3.11"
  timeout                        = 30
  memory_size                    = 256
  kms_key_arn                    = aws_kms_key.uptime_monitor.arn
  reserved_concurrent_executions = 10
  source_code_hash               = data.archive_file.api_handler_zip.output_base64sha256

  environment {
    variables = {
      CHECKS_TABLE_NAME        = aws_dynamodb_table.uptime_checks.name
      URLS_TABLE_NAME          = aws_dynamodb_table.monitored_urls.name
      LATEST_STATUS_TABLE_NAME = aws_dynamodb_table.latest_status.name
      AWS_REGION               = var.aws_region
      ALLOWED_ORIGINS          = join(",", local.cors_allowed_origins)
      METRIC_NAMESPACE         = local.metric_namespace
    }
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.api_handler_dlq.arn
  }

  tracing_config {
    mode = "Active"
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

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.uptime_api.id
  parent_id   = aws_api_gateway_rest_api.uptime_api.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy_any" {
  rest_api_id          = aws_api_gateway_rest_api.uptime_api.id
  resource_id          = aws_api_gateway_resource.proxy.id
  http_method          = "ANY"
  authorization        = "NONE"
  api_key_required     = true
  request_validator_id = aws_api_gateway_request_validator.proxy.id
}

resource "aws_api_gateway_method" "proxy_options" {
  rest_api_id          = aws_api_gateway_rest_api.uptime_api.id
  resource_id          = aws_api_gateway_resource.proxy.id
  http_method          = "OPTIONS"
  authorization        = "NONE"
  api_key_required     = false
  request_validator_id = aws_api_gateway_request_validator.proxy.id
}

resource "aws_api_gateway_request_validator" "proxy" {
  name                        = "cloudops-uptime-request-validator"
  rest_api_id                 = aws_api_gateway_rest_api.uptime_api.id
  validate_request_body       = false
  validate_request_parameters = true
}

resource "aws_api_gateway_integration" "proxy_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.uptime_api.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy_any.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_handler.invoke_arn
}

resource "aws_api_gateway_integration" "proxy_options" {
  rest_api_id = aws_api_gateway_rest_api.uptime_api.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "proxy_options" {
  rest_api_id = aws_api_gateway_rest_api.uptime_api.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Vary"                         = true
  }
}

resource "aws_api_gateway_integration_response" "proxy_options" {
  rest_api_id = aws_api_gateway_rest_api.uptime_api.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy_options.http_method
  status_code = aws_api_gateway_method_response.proxy_options.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Api-Key'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${local.primary_cors_origin}'"
    "method.response.header.Vary"                         = "'Origin'"
  }
}

resource "aws_api_gateway_deployment" "uptime_api" {
  rest_api_id = aws_api_gateway_rest_api.uptime_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.proxy_any.id,
      aws_api_gateway_method.proxy_options.id,
      aws_api_gateway_integration.proxy_lambda.id,
      aws_api_gateway_integration.proxy_options.id,
      aws_api_gateway_integration_response.proxy_options.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id           = aws_api_gateway_rest_api.uptime_api.id
  deployment_id         = aws_api_gateway_deployment.uptime_api.id
  stage_name            = "prod"
  xray_tracing_enabled  = true
  cache_cluster_enabled = true
  cache_cluster_size    = "0.5"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      caller         = "$context.identity.caller"
      user           = "$context.identity.user"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }
}

resource "aws_api_gateway_method_settings" "prod" {
  rest_api_id = aws_api_gateway_rest_api.uptime_api.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  method_path = "*/*"

  settings {
    logging_level                              = "INFO"
    metrics_enabled                            = true
    caching_enabled                            = true
    cache_data_encrypted                       = true
    cache_ttl_in_seconds                       = 60
    data_trace_enabled                         = false
    require_authorization_for_cache_control    = true
    unauthorized_cache_control_header_strategy = "SUCCEED_WITH_RESPONSE_HEADER"
  }
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/cloudops-uptime-api"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.uptime_monitor.arn

  tags = { Project = "cloudops-uptime-monitor" }
}

resource "aws_iam_role" "apigateway_cloudwatch" {
  name = "cloudops-apigateway-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "apigateway_cloudwatch" {
  role       = aws_iam_role.apigateway_cloudwatch.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "cloudwatch" {
  cloudwatch_role_arn = aws_iam_role.apigateway_cloudwatch.arn
}

resource "aws_api_gateway_api_key" "dashboard" {
  name        = "cloudops-uptime-dashboard-key"
  description = "Dashboard API key used for throttling and quota enforcement"
  enabled     = true

  tags = { Project = "cloudops-uptime-monitor" }
}

resource "aws_api_gateway_usage_plan" "dashboard" {
  name        = "cloudops-uptime-dashboard-usage-plan"
  description = "Usage plan for CloudOps Uptime Monitor dashboard API"

  api_stages {
    api_id = aws_api_gateway_rest_api.uptime_api.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  throttle_settings {
    burst_limit = var.api_throttle_burst_limit
    rate_limit  = var.api_throttle_rate_limit
  }

  quota_settings {
    limit  = var.api_daily_quota_limit
    period = "DAY"
  }

  tags = { Project = "cloudops-uptime-monitor" }
}

resource "aws_api_gateway_usage_plan_key" "dashboard" {
  key_id        = aws_api_gateway_api_key.dashboard.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.dashboard.id
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

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.uptime_monitor.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
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

resource "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "cloudops-uptime-monitor-security-headers"

  security_headers_config {
    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }

    xss_protection {
      mode_block = true
      protection = true
      override   = true
    }
  }
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

    viewer_protocol_policy     = "redirect-to-https"
    min_ttl                    = 0
    default_ttl                = 3600
    max_ttl                    = 86400
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id
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
    minimum_protocol_version       = "TLSv1.2_2021"
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

resource "aws_cloudwatch_metric_alarm" "urls_down" {
  alarm_name          = "cloudops-urls-down"
  alarm_description   = "At least one monitored URL failed the latest scheduled check"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "URLsDown"
  namespace           = local.metric_namespace
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

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
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Custom Uptime Metrics"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            [local.metric_namespace, "URLsChecked", { stat = "Sum" }],
            [".", "URLsDown", { stat = "Sum" }],
            [".", "AlertsSent", { stat = "Sum" }],
            [".", "MonitoredURLCount", { stat = "Maximum" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Status Lookup Efficiency"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            [local.metric_namespace, "StatusLookupRecordsRead", { stat = "Average" }],
            [".", "CheckRunDurationMs", { stat = "Average" }]
          ]
        }
      }
    ]
  })
}
