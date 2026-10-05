# environments/dev/terragrunt.hcl
# Development environment configuration

include "root" {
  path = find_in_parent_folders()
}

# Development environment uses local modules (for rapid iteration)
# Production should use versioned modules: git::https://github.com/company/terraform-modules.git//cloud-run?ref=v2.1.0
terraform {
  source = "${get_parent_terragrunt_dir()}/../../modules/${basename(get_terragrunt_dir())}"
}

# Each service is a separate terragrunt module
# This allows independent planning, applying, and destroying per service
# Usage: cd environments/dev/services/cloud-run && terragrunt plan

# Development services configuration
locals {
  dev_config = {
    # Development has minimal resources to reduce costs
    min_instances     = 1
    max_instances     = 10
    spanner_nodes     = 2
    bigtable_replicas = 1
    enable_backups    = false
    log_retention     = 7

    # Sampling and tracing (more aggressive in dev for debugging)
    trace_sample_rate = 1.0  # 100% sampling
    log_level         = "DEBUG"
  }
}

# Inputs specific to development environment
inputs = merge(
  yamldecode(file(find_in_parent_folders("variables/global.tfvars.yaml"))),
  yamldecode(file("${get_parent_terragrunt_dir()}/variables/dev.tfvars.yaml")),
  local.dev_config
)
