variable "aws_region" {
  default = "us-east-1"
}

variable "alert_email" {
  description = "Email address for SNS downtime alerts"
}

variable "s3_bucket_name" {
  description = "S3 bucket name for frontend"
  default     = "cloudops-uptime-monitor"
}