# Create GCP projects for each environment
resource "google_project" "env" {
  for_each = var.environments

  name            = each.value.project_name
  project_id      = each.value.project_id
  org_id          = var.organization_id
  billing_account = var.billing_account_id
}

# Create service accounts for Terraform in each project
resource "google_service_account" "terraform" {
  for_each = var.environments

  project      = google_project.env[each.key].project_id
  account_id   = "terraform-${each.key}"
  display_name = "Terraform Service Account - ${each.key}"
}

# Enable required APIs in each project
resource "google_project_service" "required_apis" {
  for_each = {
    for combo in flatten([
      for env_key, env_config in var.environments : [
        for api in var.required_apis : {
          env_key = env_key
          api     = api
        }
      ]
    ]) : "${combo.env_key}-${combo.api}" => combo
  }

  project = google_project.env[each.value.env_key].project_id
  service = each.value.api

  disable_on_destroy = false
}

# Create KMS key ring for state encryption in each project
resource "google_kms_key_ring" "terraform_state" {
  for_each = var.environments

  project  = google_project.env[each.key].project_id
  name     = "terraform-state-${each.key}"
  location = var.gcp_region
}

# Create KMS crypto key for state encryption in each project
resource "google_kms_crypto_key" "terraform_state" {
  for_each = var.environments

  name            = "terraform-state-key-${each.key}"
  key_ring        = google_kms_key_ring.terraform_state[each.key].id
  rotation_period = "7776000s"  # 90 days
  labels          = var.common_labels
}

# Create GCS bucket for Terraform state in each project
resource "google_storage_bucket" "terraform_state" {
  for_each = var.environments

  project       = google_project.env[each.key].project_id
  name          = "tf-state-${each.value.project_id}"
  location      = var.gcp_region
  force_destroy = false

  uniform_bucket_level_access = true
  versioning {
    enabled = true
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.terraform_state[each.key].id
  }

  labels = merge(
    var.common_labels,
    {
      environment = each.key
    }
  )
}

# Grant Terraform service account roles in each project
resource "google_project_iam_member" "terraform_roles" {
  for_each = {
    for combo in flatten([
      for env_key, env_config in var.environments : [
        for role in var.terraform_roles : {
          env_key = env_key
          role    = role
        }
      ]
    ]) : "${combo.env_key}-${combo.role}" => combo
  }

  project = google_project.env[each.value.env_key].project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.terraform[each.value.env_key].email}"
}

# Grant KMS permissions to Terraform service account
resource "google_kms_crypto_key_iam_member" "terraform_kms" {
  for_each = var.environments

  crypto_key_id = google_kms_crypto_key.terraform_state[each.key].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.terraform[each.key].email}"
}

# Output project IDs
output "project_ids" {
  description = "Project IDs for each environment"
  value = {
    for env_key, project in google_project.env :
    env_key => project.project_id
  }
}

# Output service account emails
output "terraform_service_accounts" {
  description = "Terraform service account emails"
  value = {
    for env_key, sa in google_service_account.terraform :
    env_key => sa.email
  }
}

# Output state bucket names
output "state_bucket_names" {
  description = "Terraform state bucket names"
  value = {
    for env_key, bucket in google_storage_bucket.terraform_state :
    env_key => bucket.name
  }
}
