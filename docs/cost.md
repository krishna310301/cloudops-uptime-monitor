# Cost Model

This project is designed to stay low-cost for a small validation workload. Actual AWS pricing varies by region and account usage; use this as a workload model rather than a bill guarantee.

## Workload Assumptions

- 10 monitored URLs
- Checks every 5 minutes
- 30-day retention
- Dashboard refresh every 30 seconds during review or validation sessions
- DynamoDB on-demand billing
- CloudFront Price Class 100

## Workload Math

```text
checks per URL per month = 12 checks/hour * 24 hours/day * 30 days = 8,640
total check records      = 10 URLs * 8,640 = 86,400 writes/month
latest status writes     = 86,400 writes/month
dashboard current rows   = 10 rows per refresh
```

## Cost Controls

- DynamoDB uses pay-per-request billing, avoiding always-on database capacity.
- Historical check records expire with TTL after `result_ttl_days`.
- The dashboard reads `latest-url-status`, avoiding reads across retained historical data.
- Lambda runs on a 5-minute EventBridge schedule and uses 256 MB memory.
- CloudFront uses `PriceClass_100`.
- Log retention is set to 365 days to preserve operational history and satisfy security scan expectations.

## Operating Notes

The important cost controls are TTL, on-demand DynamoDB, current-status reads, scheduled Lambda execution, and avoiding always-on compute. The 365-day log retention setting is intentionally more conservative than a short retention period.
