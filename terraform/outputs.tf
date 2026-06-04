output "api_url" {
  value = "https://${aws_api_gateway_rest_api.uptime_api.id}.execute-api.us-east-1.amazonaws.com/prod"
}

output "s3_website_url" {
  value = aws_s3_bucket_website_configuration.frontend.website_endpoint
}

output "lambda_url_checker_arn" {
  value = aws_lambda_function.url_checker.arn
}

output "lambda_api_handler_arn" {
  value = aws_lambda_function.api_handler.arn
}

output "sns_topic_arn" {
  value = aws_sns_topic.uptime_alerts.arn
}