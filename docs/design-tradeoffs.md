# Design Tradeoffs

## Serverless Instead Of Containers

This project uses Lambda, EventBridge, DynamoDB, API Gateway, SNS, S3, and CloudFront because the workload is periodic and bursty. There is no need to pay for always-on compute just to run checks every 5 minutes and serve a static dashboard.

Containers would make sense if the monitor needed custom network agents, long-running workers, Prometheus scraping, or multi-tenant runtime isolation. For this repository, serverless keeps the operational surface smaller and makes cost easier to reason about.

## DynamoDB Latest-Status Table

The dashboard needs the current state for each URL, not every retained check. The checker writes historical records to `uptime-checks` and also overwrites one row per URL in `latest-url-status`.

That access pattern avoids scanning retained history for every dashboard refresh. In the 10-URL, 30-day reference workload, the dashboard reads 10 current rows instead of considering 86,400 retained records.

## CloudWatch Instead Of Prometheus

CloudWatch is the natural fit for this AWS-native version of the monitor. Lambda, API Gateway, SNS, and custom application metrics are available without running a metrics backend.

Prometheus would be a good fit for the Kubernetes-based CloudOps SRE Platform, where scrape targets, service discovery, and cluster-level metrics are first-class concerns. This repository stays focused on serverless monitoring.

## Manual-Gated Deployment

CI runs automatically on every push and pull request. AWS deployment is manual through `workflow_dispatch` so infrastructure changes do not accidentally create cloud resources or send real alerts during normal development.

The workflow uses GitHub Actions OIDC for AWS role assumption, which avoids long-lived AWS access keys in repository secrets.

## Alert State Transitions

The checker compares the new result with the previous row in `latest-url-status`.

- `UP -> DOWN`: send a downtime alert
- `DOWN -> DOWN`: record status and metrics without sending repeated email
- `DOWN -> UP`: send a recovery alert
- first check `DOWN`: send an initial downtime alert

This keeps SNS useful during sustained outages without hiding recovery events.

## URL Safety

User-submitted monitor targets are treated as untrusted input. The API blocks unsafe literal targets such as localhost, private IP ranges, loopback, link-local, reserved addresses, and the AWS metadata endpoint. The checker revalidates targets at runtime and validates redirects after DNS resolution before following them.

This does not replace a full egress-control design, but it prevents the most obvious SSRF-style mistakes for a small public monitor.
