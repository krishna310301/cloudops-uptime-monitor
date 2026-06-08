# CloudOps Uptime Monitor Frontend

React dashboard for the CloudOps Uptime Monitor project.

The frontend displays monitored URLs, latest uptime state, response status, latency, and last check time. It communicates with the API Gateway endpoint provisioned by Terraform.

## Environment

Create `frontend/.env.local` for local development:

```bash
REACT_APP_API_BASE_URL=https://<api-id>.execute-api.<region>.amazonaws.com/prod
```

Use the Terraform `api_url` output for this value.

## Local Development

```bash
npm ci
npm start
```

Open:

```text
http://localhost:3000
```

## Build

```bash
npm run build
```

The production build is written to `frontend/build`.

## Deployment

GitHub Actions builds the app, syncs `frontend/build` to the private S3 frontend bucket, and invalidates the CloudFront distribution.

Required deployment secrets:

```text
AWS_ROLE_TO_ASSUME
REACT_APP_API_BASE_URL
FRONTEND_BUCKET_NAME
CLOUDFRONT_DISTRIBUTION_ID
```
