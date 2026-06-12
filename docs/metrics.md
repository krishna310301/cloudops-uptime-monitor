# Measured Results

This project uses small, reproducible measurements rather than unverifiable production traffic claims.

## Dashboard Status Lookup

The original dashboard status path scanned retained check history and selected the newest row for each URL. The improved path writes one current row per URL into `latest-url-status`, so `/status` reads current state instead of searching historical state.

Formula:

```text
checks per URL per month = 12 checks/hour * 24 hours/day * 30 days = 8,640
baseline candidate rows  = monitored URLs * 8,640
improved current rows    = monitored URLs
```

| Demo workload | Baseline candidate records | Improved current records | Reduction |
|---:|---:|---:|---:|
| 1 URL | 8,640 | 1 | 99.9884% |
| 5 URLs | 43,200 | 5 | 99.9884% |
| 10 URLs | 86,400 | 10 | 99.9884% |
| 25 URLs | 216,000 | 25 | 99.9884% |

## Custom CloudWatch Metrics

The project now publishes application-level metrics in the `CloudOps/UptimeMonitor` namespace.

| Metric | Purpose |
|---|---|
| `URLsChecked` | Count of URLs checked per scheduled run |
| `URLsDown` | Count of failing URLs per scheduled run |
| `URLCheckLatencyMs` | Per-URL HTTP response latency |
| `CheckRunDurationMs` | End-to-end Lambda checker duration |
| `AlertsSent` | Count of SNS downtime alerts published |
| `MonitoredURLCount` | Size of the monitored URL fleet |
| `StatusLookupRecordsRead` | Number of current-status rows returned to the dashboard |
| `URLAdded` | Count of dashboard add operations |
| `URLDeleted` | Count of dashboard delete operations |

## API Security And Abuse Controls

| Control | Before | After |
|---|---|---|
| Browser CORS | `*` | Configured allowed origins, defaulting to the CloudFront dashboard |
| API access | Public unauthenticated method | API key required for non-OPTIONS methods |
| Throttling | None | 10 requests/second steady-state |
| Burst limit | None | 20 requests |
| Daily quota | None | 10,000 requests/day |

API Gateway API keys are used here for throttling and quota control. For user identity and role-aware access, the production upgrade path is Cognito or IAM authorization.

## Validation Growth

| Area | Previous | Current |
|---|---:|---:|
| Lambda tests | 4 | 12 |
| Frontend tests | 1 placeholder | 4 functional dashboard tests |
| CI jobs | Terraform + deploy checks | Lambda tests, Python security scan, frontend test/build, Terraform validation, Terraform security scan |
