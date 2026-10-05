#!/bin/bash
# scripts/plan.sh
# Plan all Terraform changes across all environments
# Usage: ./scripts/plan.sh [environment] [module]
# Examples:
#   ./scripts/plan.sh dev              # Plan all modules in dev
#   ./scripts/plan.sh staging          # Plan all modules in staging
#   ./scripts/plan.sh production       # Plan all modules in production
#   ./scripts/plan.sh dev cloud-run    # Plan only cloud-run module in dev

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform/environments"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# Arguments
ENVIRONMENT="${1:-}"
MODULE="${2:-}"

# Validation
if [[ -z "$ENVIRONMENT" ]]; then
    echo -e "${RED}Error: Environment must be specified${NC}"
    echo "Usage: $0 [environment] [module]"
    echo "Environments: dev, staging, production"
    exit 1
fi

# Verify environment directory exists
if [[ ! -d "${TERRAFORM_DIR}/${ENVIRONMENT}" ]]; then
    echo -e "${RED}Error: Environment directory not found: ${TERRAFORM_DIR}/${ENVIRONMENT}${NC}"
    exit 1
fi

# Functions
plan_module() {
    local env=$1
    local mod=$2
    local module_path="${TERRAFORM_DIR}/${env}/${mod}"

    if [[ ! -d "$module_path" ]]; then
        echo -e "${YELLOW}Warning: Module path not found: $module_path${NC}"
        return 1
    fi

    echo -e "${BLUE}Planning ${env}/${mod}...${NC}"

    cd "$module_path"

    # Initialize Terragrunt
    terragrunt init --upgrade

    # Run plan
    local plan_file="tfplan_${TIMESTAMP}.out"

    if terragrunt plan -out="$plan_file" -lock=false; then
        echo -e "${GREEN}✓ Plan successful for ${env}/${mod}${NC}"
        echo "Plan saved to: $plan_file"

        # Show plan summary
        echo -e "\n${BLUE}Plan Summary:${NC}"
        terragrunt show -json "$plan_file" | jq -r '.resource_changes[] | "\(.type).\(.name): \(.change.actions[0])"' 2>/dev/null || true

        return 0
    else
        echo -e "${RED}✗ Plan failed for ${env}/${mod}${NC}"
        return 1
    fi
}

plan_environment() {
    local env=$1
    local modules_dir="${TERRAFORM_DIR}/${env}"

    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}Planning Environment: ${env}${NC}"
    echo -e "${BLUE}================================${NC}\n"

    # Get all module directories
    local modules=()
    if [[ -z "$MODULE" ]]; then
        # Plan all modules
        for item in "$modules_dir"/*; do
            if [[ -d "$item" && ! -L "$item" ]]; then
                modules+=("$(basename "$item")")
            fi
        done
    else
        # Plan specific module
        modules=("$MODULE")
    fi

    if [[ ${#modules[@]} -eq 0 ]]; then
        echo -e "${RED}No modules found in ${modules_dir}${NC}"
        return 1
    fi

    local failed_modules=()
    local success_modules=()

    for mod in "${modules[@]}"; do
        if plan_module "$env" "$mod"; then
            success_modules+=("$mod")
        else
            failed_modules+=("$mod")
        fi
        echo ""
    done

    # Summary
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}Plan Summary for ${env}${NC}"
    echo -e "${BLUE}================================${NC}"
    echo -e "${GREEN}Successful: ${#success_modules[@]}${NC}"
    for mod in "${success_modules[@]}"; do
        echo "  ✓ $mod"
    done

    if [[ ${#failed_modules[@]} -gt 0 ]]; then
        echo -e "${RED}Failed: ${#failed_modules[@]}${NC}"
        for mod in "${failed_modules[@]}"; do
            echo "  ✗ $mod"
        done
        return 1
    fi

    return 0
}

# Execute
if plan_environment "$ENVIRONMENT"; then
    echo -e "\n${GREEN}All plans completed successfully${NC}"
    exit 0
else
    echo -e "\n${RED}Some plans failed${NC}"
    exit 1
fi
