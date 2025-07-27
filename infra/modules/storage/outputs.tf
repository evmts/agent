output "file_system_id" {
  description = "ID of the EFS file system"
  value       = aws_efs_file_system.main.id
}

output "file_system_arn" {
  description = "ARN of the EFS file system"
  value       = aws_efs_file_system.main.arn
}

output "file_system_dns_name" {
  description = "DNS name of the EFS file system"
  value       = aws_efs_file_system.main.dns_name
}

output "mount_target_ids" {
  description = "IDs of the EFS mount targets"
  value       = aws_efs_mount_target.main[*].id
}

output "security_group_id" {
  description = "ID of the EFS security group"
  value       = aws_security_group.efs.id
}

output "git_repos_access_point_id" {
  description = "ID of the git repositories access point"
  value       = aws_efs_access_point.git_repos.id
}

output "git_repos_access_point_arn" {
  description = "ARN of the git repositories access point"
  value       = aws_efs_access_point.git_repos.arn
}