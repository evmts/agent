output "api_server_repository_url" {
  description = "URL of the API server ECR repository"
  value       = aws_ecr_repository.api_server.repository_url
}

output "api_server_repository_arn" {
  description = "ARN of the API server ECR repository"
  value       = aws_ecr_repository.api_server.arn
}

output "api_server_repository_name" {
  description = "Name of the API server ECR repository"
  value       = aws_ecr_repository.api_server.name
}

output "web_app_repository_url" {
  description = "URL of the web app ECR repository"
  value       = aws_ecr_repository.web_app.repository_url
}

output "web_app_repository_arn" {
  description = "ARN of the web app ECR repository"
  value       = aws_ecr_repository.web_app.arn
}

output "web_app_repository_name" {
  description = "Name of the web app ECR repository"
  value       = aws_ecr_repository.web_app.name
}