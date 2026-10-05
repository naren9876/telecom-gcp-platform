variable "gcp_region" {
  description = "GCP region for resource deployment"
  type        = string
  default     = "us-central1"
}

variable "organization_id" {
  description = "GCP Organization ID (format: numbers only, e.g., 123456789)"
  type        = string
  validation {
    condition     = can(regex("^[0-9]{10,12}$", var.organization_id))
    error_message = "Organization ID must be a 10-12 digit number."
  }
}

variable "billing_account_name" {
  description = "Display name of the billing account (e.g., 'My Billing Account')"
  type        = string
}

variable "billing_account_id" {
  description = "Billing account ID (format: XXXXXX-YYYYYY-ZZZZZZ)"
  type        = string
  validation {
    condition     = can(regex("^[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}$", var.billing_account_id))
    error_message = "Billing account ID must be in format XXXXXX-YYYYYY-ZZZZZZ."
  }
}

variable "environments" {
  description = "Environment-specific configuration"
  type = map(object({
    project_id   = string
    project_name = string
  }))
  validation {
    condition = alltrue([
      for env, config in var.environments :
      can(regex("^[a-z0-9-]{6,30}$", config.project_id))
    ])
    error_message = "Project IDs must be 6-30 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "required_apis" {
  description = "List of Google Cloud APIs to enable across all projects"
  type        = list(string)
  default = [
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "run.googleapis.com",
    "spanner.googleapis.com",
    "firestore.googleapis.com",
    "bigtable.googleapis.com",
    "bigquery.googleapis.com",
    "pubsub.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudkms.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudtrace.googleapis.com"
  ]
}

variable "terraform_roles" {
  description = "IAM roles to grant to Terraform service accounts"
  type        = list(string)
  default = [
    "roles/editor",
    "roles/iam.securityAdmin",
    "roles/resourcemanager.projectIamAdmin",
    "roles/servicemanagement.admin",
    "roles/cloudkms.admin",
    "roles/storage.admin",
    "roles/artifactregistry.admin"
  ]
}

variable "common_labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    managed_by = "terraform"
    team       = "platform"
    component  = "infrastructure"
  }
}

variable "enable_organization_policies" {
  description = "Enable organizational policy constraints (recommended for production)"
  type        = bool
  default     = false
}
