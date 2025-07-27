variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "api_image_tag" {
  description = "Docker image tag for the API server"
  type        = string
  default     = "latest"
}

variable "web_image_tag" {
  description = "Docker image tag for the web app"
  type        = string
  default     = "latest"
}

variable "enable_https" {
  description = "Enable HTTPS on the load balancer"
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ARN of the ACM certificate for HTTPS (optional)"
  type        = string
  default     = ""
}