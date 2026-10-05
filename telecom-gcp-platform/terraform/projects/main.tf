

# Get billing account data
locals {
  billing_account_id = var.billing_account_id
}

# Create GCP projects for each environment
resource "google_project" "environments" {
  for_each = var.environments

  name               = each.value.project_name
  project_id         = each.value.project_id
  org_id             = var.organization_id
  billing_account = var.billing_account_id
  auto_create_network = false

  labels = merge(
    var.common_labels,
    {
      environment = each.key
      project_type = "platform"
    }
  )

  lifecycle {
    prevent_destroy = true
  }
}

# Enable required APIs for each project
resource "google_project_service" "required_apis" {
  for_each = merge([
    for env_key, env_val in var.environments : {
      for api in var.required_apis :
      "${env_key}-${api}" => {
        project_id = env_val.project_id
        service    = api
      }
    }
  ]...)

  project            = each.value.project_id
  service            = each.value.service
  disable_on_destroy = false

  depends_on = [google_project.environments]
}

# Create Terraform service accounts per project
resource "google_service_account" "terraform" {
  for_each = var.environments

  project      = each.value.project_id
  account_id   = "terraform-sa"
  display_name = "Terraform Service Account - ${each.key}"
  description  = "Service account for Terraform automation in ${each.key} environment"

  depends_on = [google_project.environments]
}

# Grant IAM roles to Terraform service accounts
resource "google_project_iam_member" "terraform_roles" {
  for_each = merge([
    for env_key, env_val in var.environments : {
      for role in var.terraform_roles :
      "${env_key}-${role}" => {
        project_id = env_val.project_id
        role       = role
        environment = env_key
      }
    }
  ]...)

  project = each.value.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.terraform[each.value.environment].email}"

  depends_on = [google_service_account.terraform]
}

# Create GCS bucket for Terraform state backend per environment
resource "google_storage_bucket" "terraform_state" {
  for_each = var.environments

  project       = each.value.project_id
  name          = "${each.value.project_id}-terraform-state"
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
      purpose     = "terraform-state"
    }
  )

  depends_on = [google_project_service.required_apis]
}

# Create KMS key for Terraform state encryption
resource "google_kms_key_ring" "terraform_state" {
  for_each = var.environments

  project  = each.value.project_id
  name     = "${each.key}-terraform-keyring"
  location = var.gcp_region

  depends_on = [google_project_service.required_apis]
}

resource "google_kms_crypto_key" "terraform_state" {
  for_each = var.environments

  name            = "${each.key}-terraform-key"
  key_ring        = google_kms_key_ring.terraform_state[each.key].id
  rotation_period = "7776000s"

  labels = merge(
    var.common_labels,
    {
      environment = each.key
      purpose     = "state-encryption"
    }
  )
}

# Grant Terraform SA permissions to use KMS keys
resource "google_kms_crypto_key_iam_member" "terraform_state_encryption" {
  for_each = var.environments

  crypto_key_id = google_kms_crypto_key.terraform_state[each.key].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_service_account.terraform[each.key].email}"

  depends_on = [google_service_account.terraform]
}

# Grant Terraform SA permissions to manage GCS state buckets
resource "google_storage_bucket_iam_member" "terraform_state_admin" {
  for_each = var.environments

  bucket = google_storage_bucket.terraform_state[each.key].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.terraform[each.key].email}"

  depends_on = [google_storage_bucket.terraform_state]
}
