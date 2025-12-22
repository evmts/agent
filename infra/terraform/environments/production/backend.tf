# =============================================================================
# Terraform Backend Configuration
# =============================================================================
# Store state in GCS for team collaboration and state locking.
#
# Before running terraform init, create the bucket:
#   gsutil mb -l us-west1 gs://plue-terraform-state-UNIQUE_SUFFIX
#   gsutil versioning set on gs://plue-terraform-state-UNIQUE_SUFFIX

terraform {
  backend "gcs" {
    bucket = "plue-terraform-state" # UPDATE THIS with your bucket name
    prefix = "production"
  }
}

# Alternative: Local backend for initial testing
# terraform {
#   backend "local" {
#     path = "terraform.tfstate"
#   }
# }
