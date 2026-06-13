# Failure Drill

Use this drill to prove downtime detection, alerting, dashboard state, and recovery behavior.

## Goal

Validate that a failed URL is detected within one 5-minute EventBridge interval and that the failure is visible in SNS, CloudWatch metrics, Lambda logs, and the dashboard.

## Alert Behavior Under Test

- `UP -> DOWN`: sends one downtime alert.
- `DOWN -> DOWN`: records the failed check and metrics without repeated SNS email.
- `DOWN -> UP`: sends one recovery alert.

The state-transition logic is covered by Lambda unit tests. A live drill should use a controllable public endpoint so the same URL can be moved from healthy to failing and back to healthy.

## Preconditions

- Terraform apply completed successfully.
- SNS email subscription confirmed.
- Frontend deployed with `REACT_APP_API_BASE_URL`.
- If API Gateway API keys are enabled in the target stack, frontend is also deployed with `REACT_APP_API_KEY`.

## Drill Steps

1. Add a controlled test URL from the dashboard.
2. Trigger a known failure by monitoring a URL that returns a non-2xx/non-3xx response, or temporarily monitor a test endpoint you control and can take offline.
3. Wait for the next EventBridge run.
4. Confirm Lambda logs show the failed check.
5. Confirm `CloudOps/UptimeMonitor` metrics show `URLsDown >= 1` and `AlertsSent >= 1`.
6. Confirm the SNS downtime email arrives.
7. Confirm the dashboard shows the URL as `DOWN`.
8. Restore the URL and wait for the next scheduled run.
9. Confirm the dashboard returns to `UP`.

## Completed Drill: 2026-06-12

Controlled endpoint:

```text
https://d3hlcf532b9plq.cloudfront.net/drill/uptime-drill.txt
```

The drill used the project CloudFront distribution as a controllable public endpoint. The object was uploaded for the healthy state, deleted to force a `404`, then uploaded again to verify recovery.

| Event | Timestamp | Evidence |
|---|---|---|
| URL added | `2026-06-12T23:46:07Z` | API response and [dashboard UP screenshot](screenshots/failure-drill-01-url-added-up.jpg) |
| Baseline healthy check stored | `2026-06-12T23:46:08Z` | Lambda response: `status_code=200`, `is_up=true`, `latency_ms=179` |
| Failure started | `2026-06-12T23:51:14Z` | CloudFront endpoint returned `404 NoSuchKey` after object deletion and invalidation |
| Failed check stored | `2026-06-12T23:51:15Z` | Lambda response and DynamoDB `latest-url-status`: `status_code=404`, `is_up=false`, `latency_ms=190` |
| SNS alert published | `2026-06-12T23:51:15Z` | Lambda log: `DOWN alert sent`; CloudWatch `AlertsSent` metric sum reached `1` |
| SNS DOWN email received | `2026-06-12T23:51Z` | Gmail receipt from AWS Notifications; [redacted email screenshot](screenshots/failure-drill-04-sns-email-alerts-redacted.jpg) |
| Repeat DOWN check deduped | `2026-06-12T23:51:55Z` | Lambda response: `status_code=404`, `is_up=false`; no second `DOWN alert sent` log line |
| Dashboard showed DOWN | `2026-06-12T23:51:41Z` | [dashboard DOWN screenshot](screenshots/failure-drill-02-dashboard-down.jpg) |
| Recovery confirmed | `2026-06-12T23:52:37Z` | Lambda response and DynamoDB `latest-url-status`: `status_code=200`, `is_up=true`, `latency_ms=179` |
| Recovery alert published | `2026-06-12T23:52:37Z` | Lambda log: `RECOVERY alert sent`; CloudWatch `AlertsSent` metric sum reached `1` for the recovery minute |
| SNS RECOVERY email received | `2026-06-12T23:52Z` | Gmail receipt from AWS Notifications; [redacted email screenshot](screenshots/failure-drill-04-sns-email-alerts-redacted.jpg) |
| Dashboard showed UP after recovery | `2026-06-12T23:53:12Z` | [dashboard recovery screenshot](screenshots/failure-drill-03-dashboard-recovered.jpg) |
| CloudWatch metric/alarm check | `2026-06-12T23:53:49Z` | `URLsDown` metric reached `1` during outage; `cloudops-urls-down` alarm exists and was `OK` after recovery |

## Metrics To Capture

- Detection latency: `failed check stored - failure started`
- Notification latency: `email received - failed check stored`
- Dashboard visibility latency: `dashboard showed DOWN - failed check stored`
- Recovery latency: `dashboard showed UP - recovery started`

Captured drill metrics:

| Metric | Result |
|---|---:|
| Detection latency | `1 second` |
| SNS publish latency | `0 seconds` from failed check log timestamp |
| SNS email receipt | Same displayed minute as DOWN and RECOVERY publish events |
| Dashboard DOWN visibility latency | `26 seconds` |
| Recovery check latency | `1 second` |
| Dashboard recovery visibility latency | `36 seconds` |
| Duplicate DOWN alerts during sustained outage | `0` repeated alerts on the second failed check |

The SNS email screenshot is intentionally redacted before committing so the public repository does not expose the unsubscribe URL or email endpoint.

## Latest Validation Status

Code-level validation is complete in the Lambda test suite:

- one downtime alert is sent for the first `UP -> DOWN` transition
- no repeated alert is sent for continued `DOWN -> DOWN` checks
- one recovery alert is sent for `DOWN -> UP`
- unsafe metadata targets are blocked before an outbound request

Live AWS evidence was captured on 2026-06-12 using the controlled CloudFront endpoint above. Do not overwrite these values unless a new drill is run end-to-end.
