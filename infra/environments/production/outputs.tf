output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.load_balancer.alb_dns_name
}

output "alb_url" {
  description = "URL to access the application"
  value       = var.enable_https ? "https://${module.load_balancer.alb_dns_name}" : "http://${module.load_balancer.alb_dns_name}"
}

output "api_url" {
  description = "URL to access the API"
  value       = var.enable_https ? "https://${module.load_balancer.alb_dns_name}/api" : "http://${module.load_balancer.alb_dns_name}/api"
}

output "ecr_api_repository_url" {
  description = "URL of the API server ECR repository"
  value       = module.ecr.api_server_repository_url
}

output "ecr_web_repository_url" {
  description = "URL of the web app ECR repository"
  value       = module.ecr.web_app_repository_url
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs_cluster.cluster_name
}

output "database_endpoint" {
  description = "Database connection endpoint"
  value       = module.database.instance_endpoint
}

output "database_secret_arn" {
  description = "ARN of the database connection secret"
  value       = module.database.connection_secret_arn
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.network.vpc_id
}

output "migrate_task_definition_arn" {
  description = "ARN of the database migration task definition"
  value       = aws_ecs_task_definition.db_migrate.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}