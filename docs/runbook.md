# Operations Runbook

## Dashboard Shows API Offline

1. Open the CloudWatch log group `/aws/lambda/cloudops-api-handler`.
2. Check API Gateway `4XXError` and `5XXError` metrics for the `prod` stage.
3. Verify the frontend was built with `REACT_APP_API_BASE_URL` and `REACT_APP_API_KEY`.
4. Confirm the API key is attached to `cloudops-uptime-dashboard-usage-plan`.
5. Confirm the request origin is in `allowed_cors_origins`, or that the deployment is using the generated CloudFront origin default.

## URL Checks Are Not Running

1. Confirm the EventBridge rule `cloudops-uptime-schedule` is enabled.
2. Open `/aws/lambda/cloudops-url-checker` logs and check the most recent invocation.
3. Check Lambda `Errors` and `Duration` metrics.
4. Confirm the Lambda role can write to DynamoDB, publish SNS, publish CloudWatch custom metrics, and write logs.
5. Validate that the monitored URL table contains at least one URL.

## Alerts Are Not Arriving

1. Confirm the SNS email subscription is confirmed.
2. Check the URL checker logs for `Alert sent`.
3. Check the `AlertsSent` custom metric.
4. Verify the Lambda role has `sns:Publish` permission to the alert topic.
5. Check spam/quarantine for the SNS email.

## Dashboard Status Looks Stale

1. Compare the dashboard timestamp with the latest item in `latest-url-status`.
2. Check the URL checker logs for the affected URL.
3. Confirm `StatusLookupRecordsRead` is greater than zero when the dashboard refreshes.
4. Delete and re-add the URL if the monitored URL list and latest-status table are inconsistent.

## API Throttling Or Quota Hit

1. Inspect API Gateway usage plan metrics.
2. Confirm traffic source and whether repeated dashboard refreshes, scripts, or failed clients are driving usage.
3. Temporarily raise `api_throttle_rate_limit`, `api_throttle_burst_limit`, or `api_daily_quota_limit` only if the traffic is expected.
4. For public or shared access, migrate from API key controls to Cognito or IAM authorization.

## Rollback

1. Revert the last application commit.
2. Run local validation:

```bash
PYTHONPATH=. python -m unittest discover -s tests -v
cd frontend && npm test -- --watchAll=false && npm run build
cd ../terraform && terraform fmt -check && terraform validate
```

3. Redeploy through the manual GitHub Actions workflow after checks pass.
