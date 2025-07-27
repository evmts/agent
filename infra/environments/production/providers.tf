provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "production"
      Project     = "plue"
      ManagedBy   = "terraform"
    }
  }
}