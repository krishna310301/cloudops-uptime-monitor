# Security Notes

## Implemented Controls

- API Gateway requires an API key for dashboard API calls except CORS preflight.
- API Gateway usage plan limits dashboard traffic to 10 requests/second, 20 burst requests, and 10,000 requests/day by default.
- CORS is restricted to configured origins, defaulting to the CloudFront dashboard domain.
- URL submission blocks localhost, private IP ranges, loopback, link-local, reserved targets, AWS metadata IP, userinfo credentials, and non-http schemes.
- The checker revalidates monitor targets at runtime and blocks redirects to unsafe resolved addresses before following them.
- The frontend S3 bucket blocks public access and is read through CloudFront Origin Access Control.
- The frontend bucket has versioning and server-side encryption enabled.
- DynamoDB tables use TTL for retained check history, point-in-time recovery, and customer-managed KMS encryption.
- SNS, Lambda environment variables, SQS dead-letter queues, and CloudWatch log groups use the project customer-managed KMS key.
- Lambda functions have X-Ray tracing enabled for request-level debugging.
- Lambda functions send failed asynchronous invocations to SQS dead-letter queues with 14-day retention.
- CloudWatch log groups retain logs for 365 days.
- Lambda IAM permissions are scoped to the required DynamoDB tables, SNS topic, SQS queues, log groups, X-Ray writes, and custom CloudWatch metric namespace.
- GitHub Actions deployment uses AWS OIDC role assumption instead of long-lived AWS access keys.

## Known Tradeoffs

- API Gateway API keys are not user identity. They are used here for throttling, quotas, and basic abuse control for a low-cost single-operator deployment.
- A production multi-user dashboard should use Cognito, IAM authorization, or another identity provider.
- The dashboard API key is present in the browser build, so it should be treated as a traffic-control key, not a secret.
- URL checks originate from Lambda public egress. A production monitor may need multiple regions or controlled network vantage points.
- DNS can change after validation. For stricter SSRF protection, run checks through controlled egress with network firewall rules or an allowlist model.

## Recommended Production Upgrades

- Replace API key-only access with Cognito authentication and role-aware authorization.
- Add AWS WAF in front of API Gateway or CloudFront for managed rule protections.
- Add multi-region checker Lambdas to distinguish local network failures from regional failures.
- Add explicit alert publication retry policies or EventBridge routing for multi-subscriber notifications.
- Store failure drill artifacts in `docs/screenshots/` after each validation run.
