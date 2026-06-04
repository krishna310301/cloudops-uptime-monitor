# ☁️ CloudOps Uptime Monitor

A production-grade, serverless website uptime monitoring system built on AWS. Automatically checks website availability every 5 minutes, stores historical data, sends alerts on downtime, and displays live status through a React dashboard.

**Live Dashboard:** https://d3hlcf532b9plq.cloudfront.net

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
- **Historical data** — All check results stored in DynamoDB
- **Add/remove URLs** — API endpoints to manage monitored websites
- **Full observability** — CloudWatch dashboard tracking Lambda invocations, errors, duration, API Gateway metrics
- **Infrastructure as Code** — entire stack provisioned with Terraform
- **CI/CD pipeline** — GitHub Actions validates Terraform, deploys Lambda functions, builds and deploys frontend on every push

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | React, S3, CloudFront |
| API | API Gateway, Lambda (Python) |
| Scheduler | EventBridge |
| Database | DynamoDB |
| Alerts | SNS |
| Monitoring | CloudWatch Logs, Metrics, Alarms, Dashboard |
| Infrastructure | Terraform |
| CI/CD | GitHub Actions |

---

## AWS Services Used

- **Lambda** — serverless URL checker and API handler
- **DynamoDB** — stores uptime check results and monitored URLs
- **EventBridge** — scheduled rule triggering checks every 5 minutes
- **API Gateway** — REST API for dashboard communication
- **SNS** — email alerts on downtime detection
- **S3** — hosts React frontend build
- **CloudFront** — CDN serving frontend globally over HTTPS
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
└── .github/
    └── workflows/
        └── deploy.yml      # CI/CD pipeline
```

---

## API Endpoints

| Method | Endpoint | Description |
|---|---|---|
| GET | /status | Get latest uptime results for all URLs |
| GET | /urls | List all monitored URLs |
| POST | /urls | Add a new URL to monitor |
| DELETE | /urls/{url} | Remove a URL from monitoring |

---

## CI/CD Pipeline

Every push to `main` automatically:

1. **Validates Terraform** — runs `terraform validate` and `terraform fmt -check`
2. **Deploys Lambda functions** — zips and updates both Lambda functions
3. **Builds and deploys frontend** — runs `npm run build`, syncs to S3, invalidates CloudFront cache

---

## CloudWatch Monitoring

Three alarms configured:

- `cloudops-url-checker-errors` — fires when Lambda errors ≥ 1
- `cloudops-url-checker-duration` — fires when avg duration ≥ 25 seconds
- `cloudops-api-5xx-errors` — fires when API Gateway 5XX errors ≥ 5

All alarms publish to SNS for email notification.

Dashboard: **CloudOps-Uptime-Monitor** in AWS CloudWatch console.

---

## Infrastructure

All AWS resources provisioned with Terraform:

- 2 DynamoDB tables
- 2 Lambda functions
- 1 IAM role with least-privilege policies
- 1 EventBridge rule + target
- 1 API Gateway REST API
- 1 SNS topic + email subscription
- 1 S3 bucket with static website hosting
- 3 CloudWatch alarms

---

## Resume Bullets

```
- Built and deployed a serverless website uptime monitoring application using
  React, S3, CloudFront, API Gateway, Lambda, DynamoDB, EventBridge, SNS,
  and Terraform across a full production-grade AWS architecture.

- Implemented scheduled health checks every 5 minutes tracking website
  availability, response latency, status codes, and uptime history with
  SNS email alerts on downtime detection.

- Configured production observability using CloudWatch Logs, custom metrics,
  alarms, and dashboards; automated full deployment via GitHub Actions CI/CD
  with Terraform validation, Lambda deploys, and S3 frontend sync on every push.
```