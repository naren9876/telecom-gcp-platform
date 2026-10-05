# Enterprise-Grade Terraform Structure Guide

This guide explains the enterprise-standard Terraform/Terragrunt structure and how to use it effectively.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Directory Structure](#directory-structure)
3. [Terragrunt Pattern](#terragrunt-pattern)
4. [Variable Management](#variable-management)
5. [Workflow](#workflow)
6. [Best Practices](#best-practices)
7. [Common Commands](#common-commands)
8. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

The enterprise structure uses **Terragrunt** to eliminate repetition and enforce consistency across environments.

### Key Principles

```
┌─────────────────────────────────────────────────┐
│ DRY Principle: Don't Repeat Yourself            │
├─────────────────────────────────────────────────┤
│ • Single module source of truth                 │
│ • Environment-specific overrides only           │
│ • Shared variables merged at runtime            │
│ • Automatic provider/backend generation         │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│ State Management: Separate & Secure             │
├─────────────────────────────────────────────────┤
│ • One state file per environment per module     │
│ • Encrypted state backends                      │
│ • Automatic state locking                       │
│ • No shared state between environments          │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│ Module Design: Composable & Reusable           │
├─────────────────────────────────────────────────┤
│ • Functional modules (cloud-run, databases)     │
│ • No hard-coded environment values              │
│ • Comprehensive inputs and outputs              │
│ • Full documentation and examples               │
└─────────────────────────────────────────────────┘
```

---

## Directory Structure

### Complete Enterprise Layout

```
telecom-microservices/
├── .pre-commit-config.yaml           # Pre-commit hooks for quality
├── .gitignore
├── .github/                          # GitHub Actions (if using)
│   └── workflows/
│       └── terraform-ci.yml
│
├── terraform/
│   ├── terragrunt.hcl                # ROOT: DRY configuration
│   │
│   ├── modules/                      # Reusable, versioned modules
│   │   ├── cloud-run/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   ├── versions.tf
│   │   │   ├── README.md             # REQUIRED documentation
│   │   │   ├── CHANGELOG.md
│   │   │   └── examples/
│   │   │       ├── basic/
│   │   │       │   ├── main.tf
│   │   │       │   └── terraform.tfvars
│   │   │       └── complete/
│   │   │           ├── main.tf
│   │   │           └── terraform.tfvars
│   │   │
│   │   ├── databases/
│   │   │   ├── main.tf
│   │   │   ├── spanner.tf
│   │   │   ├── firestore.tf
│   │   │   ├── bigtable.tf
│   │   │   ├── bigquery.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   ├── versions.tf
│   │   │   └── README.md
│   │   │
│   │   ├── networking/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   ├── versions.tf
│   │   │   └── README.md
│   │   │
│   │   ├── iam/
│   │   │   ├── main.tf
│   │   │   ├── service-accounts.tf
│   │   │   ├── roles.tf
│   │   │   ├── workload-identity.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── README.md
│   │   │
│   │   ├── secrets/
│   │   │   └── [similar structure]
│   │   │
│   │   └── monitoring/
│   │       └── [similar structure]
│   │
│   ├── environments/
│   │   ├── _common/                  # Shared across all envs
│   │   │   ├── provider.tf
│   │   │   ├── remote_state.tf
│   │   │   ├── versions.tf
│   │   │   └── locals.tf
│   │   │
│   │   ├── dev/                      # Development environment
│   │   │   ├── terragrunt.hcl        # Dev-specific config
│   │   │   ├── dev.tfvars            # Dev-specific variables
│   │   │   ├── cloud-run/            # Module-specific config
│   │   │   │   ├── terragrunt.hcl
│   │   │   │   └── override.tfvars
│   │   │   ├── databases/
│   │   │   ├── networking/
│   │   │   └── [all modules]
│   │   │
│   │   ├── staging/                  # Staging environment
│   │   │   ├── terragrunt.hcl
│   │   │   ├── staging.tfvars
│   │   │   └── [modules]
│   │   │
│   │   └── production/               # Production environment
│   │       ├── terragrunt.hcl
│   │       ├── production.tfvars
│   │       ├── production-override.tfvars
│   │       └── [modules]
│   │
│   └── variables/                    # Shared variable definitions
│       ├── global.tfvars.yaml        # Global variables
│       ├── dev.tfvars.yaml           # Dev overrides
│       ├── staging.tfvars.yaml       # Staging overrides
│       └── production.tfvars.yaml    # Production overrides
│
├── tests/
│   ├── terratest/                    # Go-based integration tests
│   │   ├── go.mod
│   │   ├── go.sum
│   │   ├── cloud_run_test.go
│   │   ├── databases_test.go
│   │   └── integration_test.go
│   │
│   ├── unit/                         # Terraform unit tests
│   │   ├── cloud-run.tf
│   │   └── databases.tf
│   │
│   └── integration/                  # Integration test configs
│       ├── services_test.tf
│       └── end-to-end.tf
│
├── scripts/
│   ├── plan.sh                       # Plan all environments
│   ├── apply.sh                      # Apply with safeguards
│   ├── destroy.sh                    # Destroy with confirmation
│   ├── validate.sh                   # Validate all configs
│   ├── fmt.sh                        # Format all files
│   ├── init.sh                       # Initialize all envs
│   └── migrate.sh                    # Handle state migrations
│
├── docs/
│   ├── SETUP.md                      # Initial setup guide
│   ├── WORKFLOW.md                   # Development workflow
│   ├── MODULES.md                    # Module reference
│   ├── VARIABLES.md                  # Variable documentation
│   ├── TROUBLESHOOTING.md            # Common issues & fixes
│   └── CONTRIBUTING.md               # Contribution guidelines
│
└── .gitlab-ci.yml                    # CI/CD pipeline
```

---

## Terragrunt Pattern

### Root terragrunt.hcl (Eliminates Repetition)

The root configuration handles:
- Variable loading (global + environment-specific)
- Provider configuration
- Remote state setup
- Common backend config

```hcl
# Root terragrunt.hcl
locals {
  environment = split("/", get_terragrunt_dir())[1]
  global_vars = yamldecode(file("${get_parent_terragrunt_dir()}/variables/global.tfvars.yaml"))
  env_vars = yamldecode(file("${get_parent_terragrunt_dir()}/variables/${local.environment}.tfvars.yaml"))
  merged_vars = merge(local.global_vars, local.env_vars)
}

terraform {
  source = "${get_parent_terragrunt_dir()}/../../modules/${basename(get_terragrunt_dir())}"
}

remote_state {
  backend = "gcs"
  config = {
    bucket = "terraform-state-${local.environment}"
    prefix = "terraform/state"
  }
}

generate "provider" {
  path = "provider.tf"
  contents = <<-EOF
    provider "google" {
      project = "${local.merged_vars.gcp_project_id}"
    }
  EOF
}

inputs = local.merged_vars
```

### Environment terragrunt.hcl (Minimal Override)

```hcl
# environments/dev/terragrunt.hcl
include "root" {
  path = find_in_parent_folders()
}

locals {
  dev_config = {
    min_instances = 1
    max_instances = 10
  }
}

inputs = merge(
  yamldecode(file(find_in_parent_folders("variables/global.tfvars.yaml"))),
  yamldecode(file("${get_parent_terragrunt_dir()}/variables/dev.tfvars.yaml")),
  local.dev_config
)
```

**Key Benefits:**
- ✅ No repetition of provider config
- ✅ No repetition of backend config
- ✅ Variables merged automatically
- ✅ One source of truth per concern

---

## Variable Management

### Hierarchy (From Most to Least Specific)

```
1. Command-line: terraform apply -var="key=value"
2. Environment-specific override: production-override.tfvars
3. Environment-specific: production.tfvars
4. Global variables: global.tfvars.yaml
5. Default values in variables.tf
```

### Global Variables (shared across all envs)

**variables/global.tfvars.yaml:**
```yaml
gcp_region: "us-central1"
project_name: "telecom"

services:
  user-service:
    image: "gcr.io/project/user-service:latest"
    memory: "512Mi"
  billing-service:
    image: "gcr.io/project/billing-service:latest"
    memory: "256Mi"

pubsub_topics:
  - name: "user-events"
    retention_days: 7
  - name: "usage-events"
    retention_days: 7
```

### Environment-Specific Variables

**variables/dev.tfvars.yaml:**
```yaml
min_instances: 1
max_instances: 10
enable_backups: false
log_level: "DEBUG"
```

**variables/production.tfvars.yaml:**
```yaml
min_instances: 3
max_instances: 100
enable_backups: true
enable_cmek: true
log_level: "INFO"
```

### Variable Precedence Example

```
Global Setting: "log_level: INFO"
Production Override: "log_level: INFO"
Result: INFO (as expected)

Global Setting: "min_instances: 2"
Dev Override: "min_instances: 1"
Result: 1 (environment-specific wins)

Global Setting: 512Mi memory
Service Override: 1024Mi memory
Result: 1024Mi (most specific wins)
```

---

## Workflow

### 1. Daily Development Workflow

```bash
# Initialize all environments
./scripts/init.sh

# Make changes
vim terraform/modules/cloud-run/main.tf
vim terraform/variables/global.tfvars.yaml

# Validate changes
./scripts/validate.sh dev

# Plan changes
./scripts/plan.sh dev

# Review plan
terraform show tfplan_*.out

# Apply to dev
./scripts/apply.sh dev

# Test deployment
curl https://api.dev.telecom-app.com/health
```

### 2. Promoting to Staging

```bash
# Plan staging (same code, different variables)
./scripts/plan.sh staging

# Review staging plan
# (Should reflect staging-specific variables: 2 min instances, staging domain, etc.)

# Apply to staging
./scripts/apply.sh staging --auto-approve

# Run integration tests
cd tests/integration
./run-integration-tests.sh --env staging
```

### 3. Promoting to Production

```bash
# Plan production
./scripts/plan.sh production

# Review production plan
# (Should show: 3 min instances, multi-region, CMEK, etc.)

# Request approval (in CI/CD pipeline)
# gitlab-runner will require human approval before applying

# Apply to production
./scripts/apply.sh production --require-approval

# Monitor deployment
gcloud logging read "severity>=ERROR" --limit 50
gcloud monitoring dashboards list --filter="telecom*"
```

---

## Best Practices

### 1. DRY Principle

✅ **GOOD: Shared in global.tfvars.yaml**
```yaml
naming_convention: "${project}-${component}-${environment}"
common_labels:
  project: "telecom"
  managed_by: "terraform"
```

❌ **BAD: Repeated in every module**
```hcl
# In dev/cloud-run/main.tf
resource "google_cloud_run_service" "service" {
  name = "telecom-user-service-dev"
  labels = {
    project = "telecom"
    managed_by = "terraform"
  }
}

# In staging/cloud-run/main.tf (repeated!)
resource "google_cloud_run_service" "service" {
  name = "telecom-user-service-staging"
  labels = {
    project = "telecom"
    managed_by = "terraform"
  }
}
```

### 2. State Isolation

✅ **GOOD: Separate state per environment**
```
Development State: gs://terraform-state-dev/
Staging State: gs://terraform-state-staging/
Production State: gs://terraform-state-production/
```

❌ **BAD: Shared state**
```
All Environments: gs://terraform-state/
# Risk: One mistake affects all environments
```

### 3. Module Documentation

✅ **GOOD: Complete README**
```markdown
# Cloud Run Module

## Features
- Serverless compute
- Auto-scaling
- Health checks

## Usage
[examples provided]

## Inputs
[all documented]

## Outputs
[all documented]

## Testing
[how to test this module]
```

❌ **BAD: No documentation**
```
# modules/cloud-run/
# Only has main.tf, variables.tf
# No examples, no README
```

### 4. Variable Validation

✅ **GOOD: Validate inputs**
```hcl
variable "environment" {
  type = string
  validation {
    condition = contains(["dev", "staging", "production"], var.environment)
    error_message = "Invalid environment"
  }
}

variable "min_instances" {
  type = number
  validation {
    condition = var.min_instances > 0 && var.min_instances <= 100
    error_message = "Min instances must be 1-100"
  }
}
```

❌ **BAD: No validation**
```hcl
variable "environment" {
  type = string
}
# Anyone can pass any value
```

### 5. Testing Strategy

✅ **GOOD: Multiple test levels**
```
1. Pre-commit: terraform fmt, tfsec, validate
2. Unit Tests: terraform test
3. Integration Tests: terratest (Go)
4. E2E Tests: actual deployment and verification
```

❌ **BAD: No testing**
```
Deploy → Hope it works
```

---

## Common Commands

### Planning

```bash
# Plan all modules in environment
terragrunt plan-all --terragrunt-working-dir terraform/environments/dev

# Plan specific module
cd terraform/environments/dev/cloud-run
terragrunt plan

# Show detailed plan
terragrunt show -json tfplan.out | jq .
```

### Applying

```bash
# Apply with parallelization
terragrunt apply-all --terragrunt-working-dir terraform/environments/dev

# Apply single module
cd terraform/environments/dev/networking
terragrunt apply

# Apply with auto-approval (CI/CD only!)
terragrunt apply -auto-approve
```

### Validation & Quality

```bash
# Format all Terraform files
terragrunt fmt --terragrunt-recursive

# Validate all configurations
terragrunt validate-all --terragrunt-working-dir terraform/

# Security scanning with tfsec
terragrunt run-all tfsec

# Documentation generation
terragrunt run-all terraform-docs

# Pre-commit hooks
pre-commit run --all-files
```

### State Management

```bash
# List state resources
terragrunt state list

# Show resource details
terragrunt state show 'google_cloud_run_service.services["user-service"]'

# Manual state editing (dangerous!)
terragrunt state rm 'google_cloud_run_service.services["billing-service"]'

# Lock state
terragrunt force-unlock <LOCK-ID>
```

### Debugging

```bash
# Enable debug logging
TF_LOG=DEBUG terragrunt apply

# Show Terragrunt inputs
terragrunt metadata

# Inspect generated files
cat .terragrunt-cache/*/main.tf
```

---

## Troubleshooting

### Problem: Different variables between environments

**Solution: Verify variable hierarchy**
```bash
# Check merged variables
terragrunt metadata | jq .inputs

# Verify global variables
cat terraform/variables/global.tfvars.yaml

# Verify environment overrides
cat terraform/variables/${ENVIRONMENT}.tfvars.yaml
```

### Problem: State lock timeout

**Solution: Clear stuck lock**
```bash
# Find lock ID
terragrunt list-outputs
terraform state list

# Force unlock
terragrunt force-unlock <LOCK-ID>

# Verify lock cleared
terraform state list
```

### Problem: Plan shows destroying production resources

**Solution: Verify you're in correct environment**
```bash
# Check current environment
echo $PWD  # Should be terraform/environments/production/

# Verify state backend
terragrunt metadata | jq .environment

# Check variables
terragrunt metadata | jq .inputs.environment
```

### Problem: "No matching version" for provider

**Solution: Update provider version**
```bash
# In versions.tf
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"  # <- Update this
    }
  }
}

# Then
terragrunt init --upgrade
```

### Problem: Variable merge not working

**Solution: Debug variable loading**
```bash
# Check YAML syntax
yamllint terraform/variables/*.yaml

# Verify file exists
ls -la terraform/variables/${ENVIRONMENT}.tfvars.yaml

# Test merge manually
cat terraform/variables/global.tfvars.yaml
cat terraform/variables/${ENVIRONMENT}.tfvars.yaml
# Manual merge to verify
```

---

## Migration from Old Structure

If migrating from the simpler structure to enterprise:

### Step 1: Create Terragrunt Files

```bash
cp terragrunt-template.hcl terraform/terragrunt.hcl
for env in dev staging production; do
  mkdir -p terraform/environments/$env
  cp terragrunt-env-template.hcl terraform/environments/$env/terragrunt.hcl
done
```

### Step 2: Migrate Variables

```bash
# Convert .tfvars files to .yaml
# Update all environment overrides to YAML format
```

### Step 3: Test Migration

```bash
# Plan without changes
terragrunt plan-all

# Should show no changes
# State should remain unchanged
```

### Step 4: Gradual Rollout

```bash
# Migrate dev first
# Test thoroughly
# Migrate staging
# Migrate production (with extra care)
```

---

## Next Steps

1. ✅ Review the directory structure
2. ✅ Understand Terragrunt pattern
3. ✅ Study variable hierarchy
4. ✅ Practice with dev environment
5. ✅ Run pre-commit hooks
6. ✅ Execute test suite
7. ✅ Plan changes with `terragrunt plan-all`
8. ✅ Apply to dev with `terragrunt apply-all`

---

**Document Version:** 1.0  
**Last Updated:** October 2026  
**Status:** Production Ready
