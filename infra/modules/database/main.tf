resource "random_password" "master" {
  length  = 32
  special = true
}

# Store password in Secrets Manager
resource "aws_secretsmanager_secret" "database_password" {
  name                    = "${var.environment}-plue-db-password"
  recovery_window_in_days = 7

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "database_password" {
  secret_id     = aws_secretsmanager_secret.database_password.id
  secret_string = random_password.master.result
}

# Database subnet group
resource "aws_db_subnet_group" "main" {
  name       = "${var.environment}-plue-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.environment}-plue-db-subnet-group"
  })
}

# Security group for RDS
resource "aws_security_group" "database" {
  name        = "${var.environment}-plue-db-sg"
  description = "Security group for Plue RDS database"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.environment}-plue-db-sg"
  })
}

# Ingress rules will be defined in the root module to avoid circular dependencies

# Egress rule
resource "aws_security_group_rule" "database_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.database.id
}

# RDS instance
resource "aws_db_instance" "main" {
  identifier = "${var.environment}-plue-db"

  # Engine configuration
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Storage configuration
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  # Database configuration
  db_name  = var.database_name
  username = var.database_username
  password = random_password.master.result

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false

  # Backup configuration
  backup_retention_period = var.backup_retention_period
  backup_window          = var.backup_window
  maintenance_window     = var.maintenance_window

  # High availability
  multi_az = var.multi_az

  # Protection
  deletion_protection = var.deletion_protection
  skip_final_snapshot = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.environment}-plue-db-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  # Performance Insights (free tier eligible)
  performance_insights_enabled = true
  performance_insights_retention_period = 7

  # Enhanced monitoring
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = merge(var.tags, {
    Name = "${var.environment}-plue-db"
  })
}

# CloudWatch log group for RDS logs
resource "aws_cloudwatch_log_group" "database" {
  name              = "/aws/rds/instance/${aws_db_instance.main.identifier}/postgresql"
  retention_in_days = 7

  tags = var.tags
}

# Store connection details in Secrets Manager
resource "aws_secretsmanager_secret" "database_connection" {
  name                    = "${var.environment}-plue-db-connection"
  recovery_window_in_days = 7

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "database_connection" {
  secret_id = aws_secretsmanager_secret.database_connection.id
  secret_string = jsonencode({
    engine   = "postgres"
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = aws_db_instance.main.db_name
    username = aws_db_instance.main.username
    password = random_password.master.result
    url      = "postgresql://${aws_db_instance.main.username}:${random_password.master.result}@${aws_db_instance.main.address}:${aws_db_instance.main.port}/${aws_db_instance.main.db_name}"
  })
}