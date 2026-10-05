include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "../"
}

# Dev environment uses a single dev project
locals {
  environment = "dev"
}

inputs = {
  environments = {
    dev = {
      project_id   = "telecom-dev-123"
      project_name = "Telecom Platform - Development"
    }
  }
}
