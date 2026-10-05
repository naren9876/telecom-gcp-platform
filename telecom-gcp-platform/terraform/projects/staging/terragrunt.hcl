include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

# Staging environment uses a single staging project
locals {
  environment = "staging"
}

inputs = {
  environments = {
    staging = {
      project_id   = "telecom-staging-456"
      project_name = "Telecom Platform - Staging"
    }
  }
}
