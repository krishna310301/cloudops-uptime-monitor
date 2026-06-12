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
- Frontend deployed with `REACT_APP_API_BASE_URL` and `REACT_APP_API_KEY`.
- Dashboard API key is active in the API Gateway usage plan.

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

## Evidence Table

Fill this table during the drill. Use exact timestamps from CloudWatch Logs, SNS email headers, and the dashboard.

| Event | Timestamp | Evidence |
|---|---|---|
| URL added | `YYYY-MM-DD HH:MM:SS TZ` | Dashboard screenshot or API response |
| Failure started | `YYYY-MM-DD HH:MM:SS TZ` | Test endpoint log or manual note |
| EventBridge invoked checker | `YYYY-MM-DD HH:MM:SS TZ` | Lambda log stream |
| Failed check stored | `YYYY-MM-DD HH:MM:SS TZ` | Lambda log or DynamoDB item |
| SNS alert published | `YYYY-MM-DD HH:MM:SS TZ` | Lambda log and `AlertsSent` metric |
| Email received | `YYYY-MM-DD HH:MM:SS TZ` | Email screenshot |
| Dashboard showed DOWN | `YYYY-MM-DD HH:MM:SS TZ` | Dashboard screenshot |
| Recovery confirmed | `YYYY-MM-DD HH:MM:SS TZ` | Dashboard screenshot |

## Metrics To Capture

- Detection latency: `failed check stored - failure started`
- Notification latency: `email received - failed check stored`
- Dashboard visibility latency: `dashboard showed DOWN - failed check stored`
- Recovery latency: `dashboard showed UP - recovery started`

After a real drill, copy the exact timings into this document so the project shows measured detection, alerting, dashboard visibility, and recovery behavior.

## Latest Validation Status

Code-level validation is complete in the Lambda test suite:

- one downtime alert is sent for the first `UP -> DOWN` transition
- no repeated alert is sent for continued `DOWN -> DOWN` checks
- one recovery alert is sent for `DOWN -> UP`
- unsafe metadata targets are blocked before an outbound request

Live AWS evidence still needs a controlled public endpoint and screenshots from SNS, CloudWatch, and the dashboard. Do not fabricate these timestamps; record them only after an actual drill.
