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
