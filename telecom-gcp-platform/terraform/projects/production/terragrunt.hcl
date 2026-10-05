include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

# Production environment uses a single production project
locals {
  environment = "production"
}

# Add protection against accidental destruction in production
terraform {
}

inputs = {
  environments = {
    production = {
      project_id   = "telecom-prod-789"
      project_name = "Telecom Platform - Production"
    }
  }
  enable_organization_policies = true
}
