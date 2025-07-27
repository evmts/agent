terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }

  # Backend configuration for remote state
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "plue/dev/terraform.tfstate"
  #   region = "us-east-1"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt = true
  # }
}