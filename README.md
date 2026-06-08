# ☁️ CloudOps Uptime Monitor

A production-style, serverless website uptime monitoring system built on AWS. It checks website availability every 5 minutes, stores recent status history, sends alerts on downtime, and displays live status through a React dashboard served by CloudFront.

**Live Dashboard:** https://d3hlcf532b9plq.cloudfront.net

The dashboard allows users to:
- Add URLs to monitor
- View latest uptime status for all monitored sites
- Track response latency and HTTP status codes per site
- Receive SNS email alerts when a monitored site goes down
- Auto-refreshes every 30 seconds

---

## Screenshots

### Live Dashboard
![Dashboard](docs/screenshots/dashboard.png)

### CloudWatch Monitoring
![CloudWatch](docs/screenshots/cloudwatch.png)

### CI/CD Pipeline
![Pipeline](docs/screenshots/pipeline.png)

---

## Architecture

```
React Dashboard (CloudFront + S3)
         |
         | HTTPS
         v
    API Gateway
         |
         v
  Lambda API Handler
         |
         v
      DynamoDB
         |
EventBridge (every 5 min)
         |
         v
  Lambda URL Checker
         |
    checks URLs
         |
    stores results ──► DynamoDB
         |
    if DOWN ─────────► SNS Email Alert

Observability:
CloudWatch Logs + Metrics + Alarms + Dashboard

Delivery:
Terraform IaC + GitHub Actions CI/CD
```

---

## Features

- **Automated monitoring** — EventBridge triggers URL checks every 5 minutes
- **Real-time dashboard** — React frontend showing live status, latency, response codes
- **Instant alerts** — SNS email notifications when a site goes down
- **Historical data** — Check results stored in DynamoDB with TTL-based retention
- **Add/remove URLs** — API endpoints to manage monitored websites
- **Full observability** — CloudWatch dashboard tracking Lambda invocations, errors, duration, API Gateway metrics
- **Infrastructure as Code** — entire stack provisioned with Terraform
- **CI/CD pipeline** — GitHub Actions runs Lambda tests, validates Terraform, deploys Lambda functions, builds the frontend, syncs S3, and invalidates CloudFront

---

## Tech Stack

| Layer          | Technology                                  |
| -------------- | ------------------------------------------- |
| Frontend       | React, private S3 origin, CloudFront        |
| API            | API Gateway, Lambda (Python)                |
| Scheduler      | EventBridge                                 |
| Database       | DynamoDB                                    |
| Alerts         | SNS                                         |
| Monitoring     | CloudWatch Logs, Metrics, Alarms, Dashboard |
| Infrastructure | Terraform                                   |
| CI/CD          | GitHub Actions                              |

---

## AWS Services Used

- **Lambda** — serverless URL checker and API handler
- **DynamoDB** — stores uptime check results and monitored URLs
- **EventBridge** — scheduled rule triggering checks every 5 minutes
- **API Gateway** — REST API for dashboard communication
- **SNS** — email alerts on downtime detection
- **S3** — private origin bucket for the React frontend build
- **CloudFront** — CDN serving the frontend globally over HTTPS using Origin Access Control
- **CloudWatch** — logs, metrics, alarms, and dashboard for full observability
- **IAM** — least-privilege roles for all Lambda functions
- **Terraform** — provisions and manages all infrastructure as code

---

## Project Structure

```
cloudops-uptime-monitor/
├── lambda/
│   ├── url_checker.py      # checks URLs, saves results, sends alerts
│   └── api_handler.py      # handles API Gateway requests
├── frontend/
│   └── src/
│       └── App.js          # React dashboard
├── terraform/
│   ├── main.tf             # all AWS resources
│   ├── variables.tf        # configurable variables
│   └── outputs.tf          # output values
├── tests/                  # Lambda handler unit tests
└── .github/
    └── workflows/
        └── deploy.yml      # CI/CD pipeline
```

---

## API Endpoints

| Method | Endpoint    | Description                            |
| ------ | ----------- | -------------------------------------- |
| GET    | /status     | Get latest uptime results for all URLs |
| GET    | /urls       | List all monitored URLs                |
| POST   | /urls       | Add a new URL to monitor               |
| DELETE | /urls       | Remove a URL from monitoring using JSON body |
| DELETE | /urls/{url} | Remove a URL from monitoring using encoded path |

---

## CI/CD Pipeline

Every pull request validates the project. Every push to `main` can deploy when the required AWS secrets are configured.

1. **Runs Lambda unit tests** — validates URL normalization, input validation, and TTL writes
2. **Validates Terraform** — runs `terraform validate` and `terraform fmt -check`
3. **Deploys Lambda functions** — zips and updates both Lambda functions
4. **Builds and deploys frontend** — runs `npm ci` and `npm run build`, syncs to S3, invalidates CloudFront cache

Deployment uses GitHub Actions OIDC with `AWS_ROLE_TO_ASSUME`, avoiding long-lived AWS access keys in repository secrets.

---

## CloudWatch Monitoring

Three alarms configured:

- `cloudops-url-checker-errors` — fires when Lambda errors ≥ 1
- `cloudops-url-checker-duration` — fires when avg duration ≥ 25 seconds
- `cloudops-api-handler-errors` — fires when the API handler Lambda errors ≥ 1

All alarms publish to SNS for email notification.

Dashboard: **CloudOps-Uptime-Monitor** in AWS CloudWatch console.

---

## Infrastructure

All AWS resources provisioned with Terraform:

- 2 DynamoDB tables
- 2 Lambda functions
- 1 IAM role with least-privilege policies
- 1 EventBridge rule + target
- 1 API Gateway REST API with Lambda proxy integration and prod stage
- 1 SNS topic + email subscription
- 1 private S3 bucket for frontend assets
- 1 CloudFront distribution with Origin Access Control
- 3 CloudWatch alarms
- 1 CloudWatch dashboard

---

## Quick Start

```bash
git clone https://github.com/krishna310301/cloudops-uptime-monitor.git
cd cloudops-uptime-monitor/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your email and bucket name
terraform init
terraform plan
terraform apply
```

After deployment:
1. Confirm the SNS email subscription from your inbox
2. Set `REACT_APP_API_BASE_URL` to the Terraform `api_url` output before building the frontend
3. Open the CloudFront URL from Terraform outputs
4. Add a URL from the dashboard
5. Wait for the next EventBridge check cycle (every 5 minutes)

## Local Validation

```bash
PYTHONPATH=. python -m unittest discover -s tests -v
cd frontend && npm ci && npm run build
cd ../terraform && terraform init -backend=false && terraform fmt -check && terraform validate
```

## Cleanup

```bash
cd terraform
terraform destroy
```

---
