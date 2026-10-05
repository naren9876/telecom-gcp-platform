

# Configure provider.tf generation
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-PROVIDER
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  region = local.gcp_region
}
PROVIDER
}

# Configure locals.tf generation
generate "locals" {
  path      = "locals.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-LOCALS
locals {
  gcp_region = "${local.gcp_region}"
  environment = "${local.environment}"
  organization_id = "${local.organization_id}"
  common_labels = ${jsonencode(local.common_labels)}
}
LOCALS
}

# Read global variables
locals {
  global_vars = yamldecode(file("${dirname(find_in_parent_folders())}/variables/global.tfvars.yaml"))

  # Extract commonly needed values
  gcp_region        = local.global_vars.gcp_region
  organization_id   = local.global_vars.organization_id
  billing_account_name = local.global_vars.billing_account_name
  billing_account_id = local.global_vars.billing_account_id
  common_labels     = local.global_vars.common_labels
  environments      = local.global_vars.environments
  terraform_roles   = local.global_vars.terraform_roles
  required_apis     = local.global_vars.required_apis

  # Determine current environment from path
  environment = try(regex(".*/projects/([^/]+)/", get_terragrunt_dir()), "unknown")
}

# Pass all variables to Terraform
inputs = {
  gcp_region              = local.gcp_region
  organization_id         = local.organization_id
  billing_account_name    = local.billing_account_name
  billing_account_id      = local.billing_account_id
  environments            = local.environments
  terraform_roles         = local.terraform_roles
  required_apis           = local.required_apis
  common_labels           = local.common_labels
  enable_organization_policies = false
}
