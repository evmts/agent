# =============================================================================
# Terraform Backend Configuration - Staging
# =============================================================================
# Store terraform state in GCS for team collaboration.
#
# Initialize with:
#   terraform init -backend-config="bucket=<your-staging-bucket>"

terraform {
  backend "gcs" {
    bucket = "plue-terraform-state-staging"
    prefix = "staging"
  }
}
