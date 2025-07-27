variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the service will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the ECS service"
  type        = list(string)
}

variable "ecs_cluster_id" {
  description = "ID of the ECS cluster"
  type        = string
}

variable "ecr_repository_url" {
  description = "URL of the ECR repository containing the API server image"
  type        = string
}

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

variable "cpu" {
  description = "CPU units for the task (256, 512, 1024, 2048, 4096)"
  type        = string
  default     = "256"
}

variable "memory" {
  description = "Memory for the task in MB (512, 1024, 2048, 4096, 8192, etc.)"
  type        = string
  default     = "512"
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 1
}

variable "min_capacity" {
  description = "Minimum number of tasks for auto-scaling"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of tasks for auto-scaling"
  type        = number
  default     = 3
}

variable "database_secret_arn" {
  description = "ARN of the secret containing database connection details"
  type        = string
}

variable "efs_file_system_id" {
  description = "ID of the EFS file system for git repositories"
  type        = string
}

variable "efs_access_point_id" {
  description = "ID of the EFS access point for git repositories"
  type        = string
}

variable "load_balancer_target_group_arn" {
  description = "ARN of the load balancer target group"
  type        = string
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}