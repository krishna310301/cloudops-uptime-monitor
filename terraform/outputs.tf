output "api_url" {
  description = "API Gateway base URL"
  value       = "https://${aws_api_gateway_rest_api.uptime_api.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.prod.stage_name}"
}

output "cloudfront_url" {
  description = "CloudFront URL for the React dashboard"
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID used for cache invalidation"
  value       = aws_cloudfront_distribution.frontend.id
}

output "frontend_bucket_name" {
  description = "Private S3 bucket used as the CloudFront origin"
  value       = aws_s3_bucket.frontend.bucket
}

output "lambda_url_checker_arn" {
  description = "URL checker Lambda ARN"
  value       = aws_lambda_function.url_checker.arn
}

output "lambda_api_handler_arn" {
  description = "API handler Lambda ARN"
  value       = aws_lambda_function.api_handler.arn
}

output "sns_topic_arn" {
  description = "SNS topic ARN for downtime and alarm notifications"
  value       = aws_sns_topic.uptime_alerts.arn
}
