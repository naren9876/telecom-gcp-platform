terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket  = "telecom-app-terraform-state-dev"
    prefix  = "terraform/state"
    encryption_key = ""  # Set via -backend-config in CI/CD
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# GCP Project Setup
module "gcp_project" {
  source = "../../modules/gcp-project"

  project_id = var.project_id
  region     = var.region

  required_apis = [
    "run.googleapis.com",
    "spanner.googleapis.com",
    "firestore.googleapis.com",
    "bigtable.googleapis.com",
    "pubsub.googleapis.com",
    "bigquery.googleapis.com",
    "secretmanager.googleapis.com",
    "container.googleapis.com",
    "compute.googleapis.com",
    "cloudkms.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "trace.googleapis.com",
    "servicecontrol.googleapis.com",
    "servicemanagement.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "artifactregistry.googleapis.com"
  ]
}

# Networking Setup
module "networking" {
  source = "../../modules/networking"

  project_id    = var.project_id
  region        = var.region
  environment   = var.environment
  network_name  = "telecom-vpc-${var.environment}"
  subnet_cidr   = var.subnet_cidr

  depends_on = [module.gcp_project]
}

# Secrets Management
module "secrets" {
  source = "../../modules/secrets"

  project_id  = var.project_id
  environment = var.environment

  secrets = {
    "db-password"              = var.db_password
    "spanner-key"              = var.spanner_encryption_key
    "notification-api-key"     = var.notification_api_key
    "billing-provider-key"     = var.billing_provider_key
    "jwt-signing-key"          = var.jwt_signing_key
  }

  depends_on = [module.gcp_project]
}

# IAM Setup (Service Accounts and Roles)
module "iam" {
  source = "../../modules/iam"

  project_id  = var.project_id
  environment = var.environment

  services = [
    "user-service",
    "billing-service",
    "notification-service",
    "usage-service",
    "analytics-service"
  ]

  depends_on = [module.gcp_project]
}

# Database Layer - Spanner
module "databases" {
  source = "../../modules/databases"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  # Spanner Configuration
  spanner_instance_name = "telecom-spanner-${var.environment}"
  spanner_config        = var.environment == "production" ? "multi-region-us-eu-asia1" : "regional-us-central1"
  spanner_nodes         = var.environment == "production" ? 3 : 2

  # BigTable Configuration
  bigtable_instance_name = "telecom-bigtable-${var.environment}"
  bigtable_replication   = var.environment == "production" ? "PRODUCTION" : "DEVELOPMENT"

  # Firestore Configuration
  firestore_region = var.region

  # BigQuery Configuration
  bigquery_dataset = "telecom_analytics_${replace(var.environment, "-", "_")}"

  kms_key_id = var.kms_key_id

  depends_on = [module.gcp_project, module.networking]
}

# Pub/Sub Topics and Subscriptions
module "pubsub" {
  source = "../../modules/pubsub"

  project_id  = var.project_id
  environment = var.environment

  topics = {
    "user-events"       = { retention_days = 7 }
    "usage-events"      = { retention_days = 7 }
    "billing-events"    = { retention_days = 30 }
    "notification-jobs" = { retention_days = 7 }
  }

  subscriptions = {
    "billing-service-usage"         = { topic = "usage-events", ack_deadline = 30 }
    "notification-service-billing"  = { topic = "billing-events", ack_deadline = 60 }
    "notification-service-user"     = { topic = "user-events", ack_deadline = 60 }
    "analytics-service-usage"       = { topic = "usage-events", ack_deadline = 30 }
    "analytics-service-billing"     = { topic = "billing-events", ack_deadline = 30 }
    "analytics-service-user"        = { topic = "user-events", ack_deadline = 30 }
    "bigquery-usage-events"         = { topic = "usage-events", ack_deadline = 30 }
    "bigquery-billing-events"       = { topic = "billing-events", ack_deadline = 30 }
  }

  depends_on = [module.gcp_project]
}

# Cloud Run Services
module "cloud_run" {
  source = "../../modules/cloud-run"

  project_id         = var.project_id
  region             = var.region
  environment        = var.environment
  network_name       = module.networking.network_name
  vpc_connector_id   = module.networking.vpc_connector_id

  services = var.services_config

  # Service configurations
  min_instances           = var.environment == "production" ? 3 : 1
  max_instances           = var.environment == "production" ? 100 : 10
  cpu_threshold           = 70
  memory_limit            = "512Mi"
  cpu_limit               = "1"
  timeout_seconds         = 300

  # Environment variables
  environment_variables = {
    ENVIRONMENT            = var.environment
    GCP_PROJECT_ID         = var.project_id
    SPANNER_DATABASE       = module.databases.spanner_database_name
    FIRESTORE_DATABASE     = module.databases.firestore_database_name
    BIGTABLE_INSTANCE      = module.databases.bigtable_instance_name
    PUBSUB_PROJECT_ID      = var.project_id
    LOG_LEVEL              = var.environment == "production" ? "INFO" : "DEBUG"
    ENABLE_TRACING         = "true"
    TRACE_SAMPLE_RATE      = var.environment == "production" ? "0.1" : "1.0"
  }

  # Service account bindings
  service_accounts = {
    "user-service"          = module.iam.service_accounts["user-service"].email
    "billing-service"       = module.iam.service_accounts["billing-service"].email
    "notification-service"  = module.iam.service_accounts["notification-service"].email
    "usage-service"         = module.iam.service_accounts["usage-service"].email
    "analytics-service"     = module.iam.service_accounts["analytics-service"].email
  }

  depends_on = [
    module.gcp_project,
    module.networking,
    module.databases,
    module.pubsub,
    module.iam,
    module.secrets
  ]
}

# Monitoring and Logging
module "monitoring" {
  source = "../../modules/monitoring"

  project_id  = var.project_id
  environment = var.environment

  services = [
    "user-service",
    "billing-service",
    "notification-service",
    "usage-service",
    "analytics-service"
  ]

  log_retention_days = var.environment == "production" ? 30 : 7

  notification_channels = var.notification_channels

  alert_policies = {
    "high-error-rate"          = { threshold = 0.01, duration = 300 }
    "high-latency-p99"         = { threshold = 2000, duration = 300 }
    "database-connections"     = { threshold = 800, duration = 60 }
    "cpu-utilization"          = { threshold = 80, duration = 300 }
    "memory-utilization"       = { threshold = 80, duration = 300 }
  }

  depends_on = [module.gcp_project, module.cloud_run]
}

# Backup and Recovery
module "backup_recovery" {
  source = "../../modules/backup-recovery"

  project_id  = var.project_id
  region      = var.region
  environment = var.environment

  spanner_instance  = module.databases.spanner_instance_id
  spanner_database  = module.databases.spanner_database_name
  backup_location   = "us-central1"

  enable_backups = var.environment == "production"
  backup_schedule_cron = "0 2 * * *"  # Daily at 2 AM UTC

  depends_on = [module.databases]
}

# Outputs
output "cloud_run_services" {
  description = "Cloud Run service URLs"
  value       = module.cloud_run.service_urls
}

output "spanner_database" {
  description = "Spanner database connection string"
  value       = module.databases.spanner_database_connection
  sensitive   = true
}

output "pubsub_topics" {
  description = "Pub/Sub topic names"
  value       = module.pubsub.topics
}

output "api_gateway_url" {
  description = "API Gateway endpoint"
  value       = module.cloud_run.load_balancer_url
}
