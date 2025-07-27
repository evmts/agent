output "service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.web_app.name
}

output "task_definition_arn" {
  description = "ARN of the task definition"
  value       = aws_ecs_task_definition.web_app.arn
}

output "security_group_id" {
  description = "ID of the web app security group"
  value       = aws_security_group.web_app.id
}

output "task_execution_role_arn" {
  description = "ARN of the task execution role"
  value       = aws_iam_role.task_execution.arn
}

output "task_role_arn" {
  description = "ARN of the task role"
  value       = aws_iam_role.task.arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.web_app.name
}