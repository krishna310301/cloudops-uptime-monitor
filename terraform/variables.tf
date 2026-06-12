variable "aws_region" {
  description = "AWS region for all project resources"
  type        = string
  default     = "us-east-1"
}

variable "alert_email" {
  description = "Email address for SNS downtime alerts"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket name for frontend"
  type        = string
  default     = "cloudops-uptime-monitor"
}

variable "result_ttl_days" {
  description = "Number of days to retain uptime check records in DynamoDB"
  type        = number
  default     = 30
}

variable "allowed_cors_origins" {
  description = "Browser origins allowed to call the API. Leave empty to allow only the CloudFront dashboard domain."
  type        = list(string)
  default     = []
}

variable "api_throttle_rate_limit" {
  description = "Steady-state API Gateway usage plan rate limit in requests per second"
  type        = number
  default     = 10
}

variable "api_throttle_burst_limit" {
  description = "Short burst API Gateway usage plan limit"
  type        = number
  default     = 20
}

variable "api_daily_quota_limit" {
  description = "Daily request quota for the dashboard API key"
  type        = number
  default     = 10000
}
