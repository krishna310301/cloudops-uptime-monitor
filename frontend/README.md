# CloudOps Uptime Monitor — Frontend

React dashboard for the CloudOps Uptime Monitor project.

## Overview

The frontend displays real-time uptime status for monitored websites, 
showing response codes, latency, and check history. It communicates 
with AWS API Gateway endpoints backed by Lambda and DynamoDB.

## Features

- Live uptime status for all monitored websites
- Response status code, latency, and last check timestamp per site
- Add new URLs to monitor via the dashboard
- Auto-refreshes every 30 seconds
- Responsive dark-themed UI

## Tech Stack

- React
- AWS S3 — static file hosting
- AWS CloudFront — global CDN with HTTPS
- AWS API Gateway — backend REST API
- GitHub Actions — automated build and deployment

## Local Development

**Prerequisites:** Node.js 18+

```bash
git clone https://github.com/krishna310301/cloudops-uptime-monitor.git
cd cloudops-uptime-monitor/frontend
npm install
```

Create a `.env` file in the `frontend/` directory:
# CloudOps Uptime Monitor — Frontend

React dashboard for the CloudOps Uptime Monitor project.

## Overview

The frontend displays real-time uptime status for monitored websites, 
showing response codes, latency, and check history. It communicates 
with AWS API Gateway endpoints backed by Lambda and DynamoDB.

## Features

- Live uptime status for all monitored websites
- Response status code, latency, and last check timestamp per site
- Add new URLs to monitor via the dashboard
- Auto-refreshes every 30 seconds
- Responsive dark-themed UI

## Tech Stack

- React
- AWS S3 — static file hosting
- AWS CloudFront — global CDN with HTTPS
- AWS API Gateway — backend REST API
- GitHub Actions — automated build and deployment

## Local Development

**Prerequisites:** Node.js 18+

```bash
git clone https://github.com/krishna310301/cloudops-uptime-monitor.git
cd cloudops-uptime-monitor/frontend
npm install
```

Create a `.env` file in the `frontend/` directory:
REACT_APP_API_BASE_URL=https://3c7g55lcd0.execute-api.us-east-1.amazonaws.com/prod
Start the development server:

```bash
npm start
```

Open `http://localhost:3000`

## Build

```bash
npm run build
```

Generates optimized production files in the `build/` directory.

## Deployment

Deployment is fully automated via GitHub Actions on every push to `main`:

1. Install dependencies
2. Build React app
3. Sync `build/` to S3 bucket
4. Invalidate CloudFront cache

No manual deployment steps required.

## Environment Variables

| Variable | Description |
|---|---|
| `REACT_APP_API_BASE_URL` | API Gateway base URL |

## Live Demo

**Dashboard:** https://d3hlcf532b9plq.cloudfront.net
