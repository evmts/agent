# EFS File System
resource "aws_efs_file_system" "main" {
  creation_token   = "${var.environment}-plue-efs"
  performance_mode = var.performance_mode
  throughput_mode  = var.throughput_mode
  encrypted        = var.encrypted

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-plue-efs"
  })
}

# Security group for EFS
resource "aws_security_group" "efs" {
  name        = "${var.environment}-plue-efs-sg"
  description = "Security group for Plue EFS"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.environment}-plue-efs-sg"
  })
}

# Ingress rules will be defined in the root module to avoid circular dependencies

# Egress rule
resource "aws_security_group_rule" "efs_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.efs.id
}

# EFS mount targets (one per subnet)
resource "aws_efs_mount_target" "main" {
  count = length(var.subnet_ids)

  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

# EFS Access Point for git repositories
resource "aws_efs_access_point" "git_repos" {
  file_system_id = aws_efs_file_system.main.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/git-repos"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-plue-git-repos-ap"
  })
}