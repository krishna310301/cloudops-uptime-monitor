# Security Notes

## Implemented Controls

- API Gateway requires an API key for dashboard API calls except CORS preflight.
- API Gateway usage plan limits dashboard traffic to 10 requests/second, 20 burst requests, and 10,000 requests/day by default.
- CORS is restricted to configured origins, defaulting to the CloudFront dashboard domain.
- The frontend S3 bucket blocks public access and is read through CloudFront Origin Access Control.
- The frontend bucket has versioning and server-side encryption enabled.
- DynamoDB tables use TTL for retained check history and point-in-time recovery for operational recovery.
- Lambda IAM permissions are scoped to the required DynamoDB tables, SNS topic, log groups, and custom CloudWatch metric namespace.
- GitHub Actions deployment uses AWS OIDC role assumption instead of long-lived AWS access keys.

## Known Tradeoffs

- API Gateway API keys are not user identity. They are used here for throttling, quotas, and basic abuse control because the dashboard is a small portfolio demo.
- A production multi-user dashboard should use Cognito, IAM authorization, or another identity provider.
- The dashboard API key is present in the browser build, so it should be treated as a traffic-control key, not a secret.
- URL checks originate from Lambda public egress. A production monitor may need multiple regions or controlled network vantage points.

## Recommended Production Upgrades

- Replace API key-only access with Cognito authentication and role-aware authorization.
- Add AWS WAF in front of API Gateway or CloudFront for managed rule protections.
- Add multi-region checker Lambdas to distinguish local network failures from regional failures.
- Add DLQ or retry handling for failed alert publication.
- Store failure drill artifacts in `docs/screenshots/` after each demo.
