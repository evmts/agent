#!/bin/bash
# Initialize a personal staging environment

set -euo pipefail

ENGINEER=${1:-$USER}
ENV_DIR="terraform/environments/staging-${ENGINEER}"

echo "═══════════════════════════════════════════════════════════════"
echo "  Setting up staging environment for: ${ENGINEER}"
echo "═══════════════════════════════════════════════════════════════"

# Check if directory exists
if [ ! -d "$ENV_DIR" ]; then
  echo "Creating environment directory..."

  # Check if template exists
  if [ ! -d "terraform/environments/staging-template" ]; then
    echo "Creating template..."
    mkdir -p terraform/environments/staging-template

    cat > terraform/environments/staging-template/main.tf << 'EOF'
# Per-engineer staging environment
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }

  backend "gcs" {
    bucket = "plue-terraform-state"
    prefix = "staging-ENGINEER_NAME"
  }
}

variable "engineer_name" {
  type    = string
  default = "ENGINEER_NAME"
}

variable "project_id" {
  type    = string
  default = "plue-staging"
}

variable "region" {
  type    = string
  default = "us-central1"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Reference staging-base outputs
data "terraform_remote_state" "base" {
  backend = "gcs"
  config = {
    bucket = "plue-terraform-state"
    prefix = "staging-base"
  }
}

# Create database in shared Cloud SQL
resource "google_sql_database" "database" {
  name     = "plue_${var.engineer_name}"
  instance = data.terraform_remote_state.base.outputs.sql_instance_name
  project  = var.project_id
}

# Outputs
output "url" {
  value = "https://${var.engineer_name}.staging.plue.dev"
}

output "database" {
  value = google_sql_database.database.name
}
EOF
  fi

  cp -r terraform/environments/staging-template "$ENV_DIR"

  # Update engineer name
  sed -i '' "s/ENGINEER_NAME/${ENGINEER}/g" "$ENV_DIR/main.tf"

  echo "Created $ENV_DIR - please review and commit!"
fi

cd "$ENV_DIR"

# Initialize Terraform
echo "→ Initializing Terraform..."
terraform init

# Plan
echo "→ Planning..."
terraform plan -out=tfplan

# Confirm
read -p "Apply this plan? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  terraform apply tfplan

  echo "═══════════════════════════════════════════════════════════════"
  echo "  ✓ Staging environment ready!"
  echo "  URL: https://${ENGINEER}.staging.plue.dev"
  echo "  Namespace: ${ENGINEER}"
  echo "═══════════════════════════════════════════════════════════════"
fi
