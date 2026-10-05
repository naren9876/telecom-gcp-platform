# Telecom Microservices Platform - Deployment Guide

This guide provides step-by-step instructions for deploying the telecom microservices platform on Google Cloud Platform using Terraform and GitLab CI/CD.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Environment Configuration](#environment-configuration)
4. [Infrastructure Deployment](#infrastructure-deployment)
5. [Application Deployment](#application-deployment)
6. [Verification & Testing](#verification--testing)
7. [Monitoring & Alerting Setup](#monitoring--alerting-setup)
8. [Troubleshooting](#troubleshooting)
9. [Disaster Recovery](#disaster-recovery)

---

## Prerequisites

### 1. GCP Accounts & Projects

Create three GCP projects:
- **Development**: `telecom-app-dev`
- **Staging**: `telecom-app-staging`
- **Production**: `telecom-app-production`

Ensure the following:
- Projects are linked to a billing account
- APIs are enabled (will be done by Terraform)
- Service accounts with appropriate permissions exist

### 2. Required Tools

```bash
# Google Cloud SDK
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init

# Terraform (>= 1.0)
wget https://releases.hashicorp.com/terraform/1.5.0/terraform_1.5.0_linux_amd64.zip
unzip terraform_1.5.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Docker
sudo apt-get install docker.io
sudo usermod -aG docker $USER

# GitLab Runner (for CI/CD)
curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | sudo bash
sudo apt-get install gitlab-runner

# kubectl (for future GKE migrations)
gcloud components install kubectl

# Other utilities
apt-get install jq git
```

### 3. GitLab Repository Setup

1. Create a new GitLab repository
2. Clone locally:
   ```bash
   git clone <repository-url>
   cd telecom-microservices
   ```

3. Protect branches:
   - `main` → Require 2 approvals before merge
   - `production` → Manual deployment only

---

## Initial Setup

### 1. Create GCP Service Accounts

For each environment, create service accounts for Terraform and CI/CD:

```bash
# Development environment
gcloud iam service-accounts create terraform-sa \
  --project telecom-app-dev \
  --display-name "Terraform Service Account"

gcloud iam service-accounts create gitlab-ci-sa \
  --project telecom-app-dev \
  --display-name "GitLab CI Service Account"

# Grant necessary permissions
for role in roles/editor roles/iam.serviceAccountAdmin roles/iam.securityAdmin; do
  gcloud projects add-iam-policy-binding telecom-app-dev \
    --member=serviceAccount:terraform-sa@telecom-app-dev.iam.gserviceaccount.com \
    --role=$role
done

# Create and download service account keys
gcloud iam service-accounts keys create terraform-key-dev.json \
  --iam-account=terraform-sa@telecom-app-dev.iam.gserviceaccount.com

gcloud iam service-accounts keys create gitlab-ci-key-dev.json \
  --iam-account=gitlab-ci-sa@telecom-app-dev.iam.gserviceaccount.com
```

Repeat for staging and production environments.

### 2. Create Terraform State Backend

```bash
# Create GCS bucket for Terraform state (Development)
gsutil mb -p telecom-app-dev -l us-central1 gs://telecom-app-terraform-state-dev

# Enable versioning and encryption
gsutil versioning set on gs://telecom-app-terraform-state-dev

# Create CMEK encryption key
gcloud kms keyrings create terraform-state \
  --location us-central1 \
  --project telecom-app-dev

gcloud kms keys create terraform-key \
  --location us-central1 \
  --keyring terraform-state \
  --purpose encryption \
  --project telecom-app-dev

# Grant Terraform service account access
gcloud kms keys add-iam-policy-binding terraform-key \
  --location us-central1 \
  --keyring terraform-state \
  --member=serviceAccount:terraform-sa@telecom-app-dev.iam.gserviceaccount.com \
  --role=roles/cloudkms.cryptoKeyEncrypterDecrypter \
  --project telecom-app-dev
```

Repeat for staging and production.

### 3. Configure GitLab CI/CD Variables

In GitLab, set the following project variables (Settings → CI/CD → Variables):

```
GCP_SERVICE_ACCOUNT_KEY: <base64-encoded gitlab-ci-key-dev.json>
GCP_SERVICE_ACCOUNT_KEY_PROD: <base64-encoded gitlab-ci-key-prod.json>
TF_STATE_ENCRYPTION_KEY: <CMEK key from above>
TF_STATE_ENCRYPTION_KEY_PROD: <CMEK key for production>
REGISTRY_PASSWORD: <if using private registry>
```

Encode files to base64:
```bash
base64 -w 0 gitlab-ci-key-dev.json > encoded.txt
```

### 4. Register GitLab Runner

For cloud-based CI/CD execution:

```bash
# Create GCP instance for runner
gcloud compute instances create gitlab-runner \
  --project telecom-app-dev \
  --zone us-central1-a \
  --image-family ubuntu-2204-lts \
  --image-project ubuntu-os-cloud \
  --machine-type n1-standard-2

# SSH into instance
gcloud compute ssh gitlab-runner --zone us-central1-a --project telecom-app-dev

# Install runner (inside instance)
curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | sudo bash
sudo apt-get install gitlab-runner

# Register runner
sudo gitlab-runner register \
  --url https://gitlab.com/ \
  --registration-token <token-from-gitlab> \
  --executor docker \
  --docker-image google/cloud-sdk:alpine \
  --description "Telecom Platform Runner" \
  --docker-privileged
```

---

## Environment Configuration

### 1. Create Environment Files

Create `terraform.tfvars` for each environment:

**File: `infrastructure/terraform/environments/dev/terraform.tfvars`**

```hcl
project_id              = "telecom-app-dev"
environment             = "dev"
region                  = "us-central1"
subnet_cidr             = "10.0.0.0/24"

# Database configuration
db_password             = "dev_password_123"
spanner_encryption_key  = "dev_key_123"

# API keys for external services
notification_api_key    = "dev_api_key"
billing_provider_key    = "dev_billing_key"
jwt_signing_key         = "dev_jwt_key"

# Services configuration
services_config = {
  "user-service" = {
    name                 = "user-service"
    image                = "gcr.io/telecom-app-dev/user-service:latest"
    container_port       = 8080
    health_check_path    = "/health"
    cpu_request          = "100m"
    memory_request       = "128Mi"
    env_vars             = {}
    secret_env_vars      = {
      "DB_PASSWORD" = { secret_name = "db-password", secret_version = "latest" }
    }
  }
  # ... other services
}

# Monitoring
notification_channels = [
  "projects/telecom-app-dev/notificationChannels/1234567890"
]

# Encryption
kms_key_id = "projects/telecom-app-dev/locations/us-central1/keyRings/terraform-state/cryptoKeys/terraform-key"

# Networking
api_domains = ["api.dev.telecom-app.com"]
```

**File: `infrastructure/terraform/environments/dev/variables.tf`**

```hcl
variable "project_id" {
  type        = string
  description = "GCP Project ID"
}

variable "environment" {
  type        = string
  description = "Environment (dev, staging, production)"
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "GCP region"
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR block for VPC subnet"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "Spanner database password"
}

variable "spanner_encryption_key" {
  type        = string
  sensitive   = true
  description = "Spanner encryption key"
}

variable "notification_api_key" {
  type        = string
  sensitive   = true
  description = "Notification service API key"
}

variable "billing_provider_key" {
  type        = string
  sensitive   = true
  description = "Billing provider API key"
}

variable "jwt_signing_key" {
  type        = string
  sensitive   = true
  description = "JWT signing key"
}

variable "services_config" {
  type        = any
  description = "Cloud Run services configuration"
}

variable "notification_channels" {
  type        = list(string)
  description = "Monitoring notification channel IDs"
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for encryption"
}

variable "api_domains" {
  type        = list(string)
  description = "API domain names for SSL certificates"
}
```

### 2. Create Backend Configuration

**File: `infrastructure/terraform/environments/dev/backend.tf`**

```hcl
terraform {
  backend "gcs" {
    bucket  = "telecom-app-terraform-state-dev"
    prefix  = "terraform/state"
  }
}
```

---

## Infrastructure Deployment

### 1. Validate Terraform Configuration

```bash
cd infrastructure/terraform/environments/dev

# Initialize Terraform
terraform init \
  -backend-config="bucket=telecom-app-terraform-state-dev" \
  -backend-config="encryption_key=$(grep TF_STATE_ENCRYPTION_KEY /path/to/vars.txt | cut -d= -f2)"

# Format check
terraform fmt -check -recursive ..

# Validation
terraform validate

# Security scanning (optional)
tfsec .
```

### 2. Plan Deployment

```bash
# Create and review plan
terraform plan \
  -var-file=terraform.tfvars \
  -out=tfplan

# Review output
terraform show tfplan | less
```

### 3. Apply Infrastructure

```bash
# Apply changes
terraform apply tfplan

# Save outputs
terraform output -json > outputs.json

# Note critical outputs:
API_GATEWAY_URL=$(terraform output -raw api_gateway_url)
SPANNER_DATABASE=$(terraform output -raw spanner_database)
echo "API Gateway URL: $API_GATEWAY_URL"
```

### 4. Verify Infrastructure

```bash
# Check GCP resources
gcloud run services list --project telecom-app-dev
gcloud spanner databases list --instance telecom-spanner-dev --project telecom-app-dev
gcloud firestore databases list --project telecom-app-dev

# Verify network connectivity
gcloud compute networks describe telecom-vpc-dev --project telecom-app-dev
gcloud compute networks peerings list --network telecom-vpc-dev --project telecom-app-dev
```

---

## Application Deployment

### 1. Build Services Locally (Development Only)

```bash
# Build Docker images
for service in user-service billing-service notification-service usage-service analytics-service; do
  docker build -t gcr.io/telecom-app-dev/${service}:latest services/${service}
  docker push gcr.io/telecom-app-dev/${service}:latest
done
```

### 2. CI/CD Pipeline Deployment (Production Recommended)

Push to GitLab to trigger automated deployment:

```bash
# Create feature branch
git checkout -b feature/deployment

# Make changes
git add .
git commit -m "Deploy telecom microservices platform"

# Push and create merge request
git push origin feature/deployment

# GitLab CI will:
# 1. Validate Terraform
# 2. Build Docker images
# 3. Security scans
# 4. Deploy to staging
# 5. Run integration tests
# 6. Await manual approval for production
```

### 3. Manual Production Deployment (If CI/CD Unavailable)

```bash
# Set production credentials
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/prod-key.json
export GCP_PROJECT_ID=telecom-app-production

# Deploy infrastructure
cd infrastructure/terraform/environments/production
terraform init -backend-config="bucket=telecom-app-terraform-state-production"
terraform plan -var-file=production.tfvars -out=tfplan
terraform apply tfplan

# Deploy services
for service in user-service billing-service notification-service usage-service analytics-service; do
  gcloud run deploy ${service} \
    --image gcr.io/telecom-app-production/${service}:${VERSION} \
    --region us-central1 \
    --platform managed \
    --no-allow-unauthenticated \
    --service-account ${service}-sa@telecom-app-production.iam.gserviceaccount.com \
    --memory 512Mi \
    --cpu 1 \
    --max-instances 100 \
    --min-instances 3
done
```

---

## Verification & Testing

### 1. Service Health Checks

```bash
# Get API Gateway URL
API_URL=$(terraform output -raw api_gateway_url)

# Check services
curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  $API_URL/health

# For each service
for service in user-service billing-service notification-service usage-service analytics-service; do
  gcloud run services describe ${service} --region us-central1 --project telecom-app-dev
done
```

### 2. Database Connectivity

```bash
# Test Spanner
gcloud spanner databases execute-sql telecom_transactional \
  --instance telecom-spanner-dev \
  --sql "SELECT 1" \
  --project telecom-app-dev

# Test Firestore
gcloud firestore databases describe --project telecom-app-dev

# Test BigTable
gcloud bigtable instances describe telecom-bigtable-dev --project telecom-app-dev
```

### 3. Integration Tests

```bash
# Run integration test suite
cd tests/integration
./run-integration-tests.sh \
  --host=$API_URL \
  --auth-token="$(gcloud auth print-identity-token)" \
  --environment=dev

# Check test results
cat test-results/junit.xml
```

### 4. Load Testing

```bash
# Install load testing tool
go install github.com/grafana/k6@latest

# Run load test
k6 run tests/load-testing/user-service.js \
  --vus 100 \
  --duration 5m \
  --rps 1000 \
  -e API_URL=$API_URL
```

---

## Monitoring & Alerting Setup

### 1. Create Monitoring Dashboard

```bash
# Create dashboard for service metrics
gcloud monitoring dashboards create --config-from-file=dashboards/telecom-services.yaml

# View dashboard
gcloud monitoring dashboards list --filter="displayName=telecom-*"
```

**File: `dashboards/telecom-services.yaml`**

```yaml
displayName: "Telecom Services Dashboard"
dashboardFilters: []
gridLayout:
  widgets:
    # Request rate per service
    - title: "Request Rate (requests/min)"
      xyChart:
        dataSets:
          - timeSeriesQuery:
              timeSeriesFilter:
                filter: 'resource.type="cloud_run_revision"'
    
    # Latency (p99)
    - title: "Latency P99 (ms)"
      xyChart:
        dataSets:
          - timeSeriesQuery:
              timeSeriesFilter:
                filter: 'resource.type="cloud_run_revision" AND metric.type="run.googleapis.com/request_latencies"'
    
    # Error rate
    - title: "Error Rate"
      xyChart:
        dataSets:
          - timeSeriesQuery:
              timeSeriesFilter:
                filter: 'resource.type="cloud_run_revision" AND metric.type="run.googleapis.com/request_count"'
```

### 2. Configure Alerting Policies

```bash
# High error rate alert
gcloud alpha monitoring policies create \
  --notification-channels=<channel-id> \
  --display-name="High Error Rate Alert" \
  --condition-display-name="Error rate > 1%" \
  --condition-threshold-value=0.01 \
  --condition-threshold-duration=300s
```

### 3. View Logs

```bash
# Stream logs for specific service
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=user-service" \
  --limit 50 \
  --follow \
  --format json \
  --project telecom-app-dev

# Search for errors
gcloud logging read "severity=ERROR AND resource.type=cloud_run_revision" \
  --limit 100 \
  --format json \
  --project telecom-app-dev
```

---

## Troubleshooting

### 1. Terraform Issues

**Problem**: `terraform init` fails with authentication error

```bash
# Solution: Set credentials
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account-key.json
gcloud auth application-default login
```

**Problem**: State lock timeout

```bash
# Check lock
terraform force-unlock <lock-id>
```

### 2. Cloud Run Deployment Issues

**Problem**: Service fails to start

```bash
# Check logs
gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=user-service" \
  --limit 20 \
  --format=json

# Check service details
gcloud run services describe user-service --region us-central1
```

**Problem**: 403 Permission Denied

```bash
# Verify service account has necessary permissions
gcloud projects get-iam-policy telecom-app-dev \
  --flatten="bindings[].members" \
  --format="table(bindings.role)" \
  --filter="bindings.members:serviceAccount:user-service-sa@*"
```

### 3. Database Issues

**Problem**: Cannot connect to Spanner

```bash
# Verify instance exists
gcloud spanner instances list

# Check network connectivity
gcloud compute firewall-rules list --filter="network:telecom-vpc-dev"

# Test from Cloud Shell
gcloud spanner databases execute-sql telecom_transactional \
  --instance telecom-spanner-dev \
  --sql "SELECT 1"
```

### 4. Networking Issues

**Problem**: Services cannot communicate

```bash
# Check VPC connector
gcloud compute networks vpc-access connectors describe telecom-connector \
  --region us-central1

# Verify Firewall rules
gcloud compute firewall-rules list --filter="network:telecom-vpc-dev" --format=table
```

---

## Disaster Recovery

### 1. Backup Procedures

**Automated Backups** (configured via Terraform):
- Spanner: Daily at 2 AM UTC, 30-day retention
- Firestore: Daily export to Cloud Storage
- BigTable: Weekly snapshots

### 2. Recovery Procedures

**Restore Spanner from Backup**:

```bash
# List available backups
gcloud spanner backups list --instance telecom-spanner-production

# Restore to new database
gcloud spanner databases restore telecom_transactional_restored \
  --backup <backup-id> \
  --instance telecom-spanner-production

# Verify restored database
gcloud spanner databases execute-sql telecom_transactional_restored \
  --instance telecom-spanner-production \
  --sql "SELECT COUNT(*) as user_count FROM users"

# Switch application to restored database (update connection strings)
```

**Restore Firestore**:

```bash
# List available exports
gsutil ls gs://telecom-app-backups/firestore/

# Restore collection
gcloud firestore import gs://telecom-app-backups/firestore/latest.backup
```

### 3. Rollback Procedures

**Rollback Application Deployment**:

```bash
# Get previous revision
CURRENT_REVISION=$(gcloud run services describe user-service \
  --region us-central1 \
  --format='value(status.latestRevision)')

PREVIOUS_REVISION=$(gcloud run revisions list --service user-service \
  --region us-central1 \
  --format='value(REVISION)' --limit=2 | tail -1)

# Route traffic to previous revision
gcloud run services update-traffic user-service \
  --to-revisions ${PREVIOUS_REVISION}=100 \
  --region us-central1
```

**Rollback Infrastructure**:

```bash
# Revert Terraform changes
git revert <commit-sha>
git push origin main

# Or manually destroy and reapply
terraform destroy -auto-approve
terraform apply -auto-approve
```

---

## Monitoring Checklist

After deployment, verify:

- ✅ All services are running and healthy
- ✅ Databases are accessible and populated
- ✅ Pub/Sub topics are created and subscriptions active
- ✅ Load balancer is distributing traffic
- ✅ SSL certificates are valid
- ✅ Monitoring dashboards show metrics
- ✅ Alert policies are active
- ✅ Logs are being collected
- ✅ Backups are scheduled and running
- ✅ IAM roles are properly configured

---

## Support & Escalation

For issues, escalate to:
1. **Infrastructure Team** - Platform/GCP issues
2. **Security Team** - Permission/encryption issues
3. **DevOps Team** - CI/CD pipeline failures
4. **Database Team** - Spanner/Firestore issues

Contact: platform-engineering@company.com
