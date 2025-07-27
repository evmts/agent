locals {
  tags = {
    Environment = var.environment
    Project     = "plue"
  }
}

# Network Module
module "network" {
  source = "../../modules/network"

  environment          = var.environment
  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]
  
  # Production - NAT gateway per AZ for high availability
  enable_nat_gateway = true
  single_nat_gateway = false
  
  tags = local.tags
}

# ECS Cluster
module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  environment               = var.environment
  enable_container_insights = true # Enable for production monitoring
  
  tags = local.tags
}

# ECR Repositories
module "ecr" {
  source = "../../modules/ecr"

  environment          = var.environment
  image_tag_mutability = "IMMUTABLE" # Immutable tags for production
  scan_on_push        = true         # Security scanning enabled
  
  tags = local.tags
}

# Database
module "database" {
  source = "../../modules/database"

  environment     = var.environment
  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.private_subnet_ids
  
  instance_class          = "db.t3.small"
  allocated_storage       = 50
  max_allocated_storage   = 200
  backup_retention_period = 7
  multi_az               = true  # High availability
  deletion_protection    = true  # Prevent accidental deletion
  skip_final_snapshot    = false
  
  allowed_security_group_ids = [
    module.api_server.security_group_id
  ]
  
  tags = local.tags
}

# Storage (EFS)
module "storage" {
  source = "../../modules/storage"

  environment     = var.environment
  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.private_subnet_ids
  
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  
  allowed_security_group_ids = [
    module.api_server.security_group_id
  ]
  
  tags = local.tags
}

# Load Balancer
module "load_balancer" {
  source = "../../modules/load-balancer"

  environment     = var.environment
  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.public_subnet_ids
  
  enable_https               = var.enable_https
  certificate_arn           = var.certificate_arn
  enable_deletion_protection = true # Prevent accidental deletion
  
  tags = local.tags
}

# API Server
module "api_server" {
  source = "../../modules/api-server"

  environment     = var.environment
  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.private_subnet_ids
  ecs_cluster_id  = module.ecs_cluster.cluster_id
  
  ecr_repository_url = module.ecr.api_server_repository_url
  image_tag          = var.api_image_tag
  
  cpu           = "512"
  memory        = "1024"
  desired_count = 2    # Higher availability
  min_capacity  = 2
  max_capacity  = 10   # Higher scaling limit
  
  database_secret_arn    = module.database.connection_secret_arn
  efs_file_system_id     = module.storage.file_system_id
  efs_access_point_id    = module.storage.git_repos_access_point_id
  load_balancer_target_group_arn = module.load_balancer.api_target_group_arn
  
  tags = local.tags
  
  depends_on = [module.database]
}

# Web App
module "web_app" {
  source = "../../modules/web-app"

  environment     = var.environment
  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.private_subnet_ids
  ecs_cluster_id  = module.ecs_cluster.cluster_id
  
  ecr_repository_url = module.ecr.web_app_repository_url
  image_tag          = var.web_image_tag
  
  cpu           = "512"
  memory        = "1024"
  desired_count = 2    # Higher availability
  min_capacity  = 2
  max_capacity  = 10   # Higher scaling limit
  
  api_endpoint = "https://${module.load_balancer.alb_dns_name}/api"
  load_balancer_target_group_arn = module.load_balancer.web_target_group_arn
  
  tags = local.tags
}

# SNS Topic for Alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.environment}-plue-alerts"

  tags = local.tags
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.sns_alert_email
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  alarm_name          = "${var.environment}-plue-db-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Database CPU utilization is too high"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = module.database.instance_id
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "database_storage" {
  alarm_name          = "${var.environment}-plue-db-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "5368709120" # 5GB in bytes
  alarm_description   = "Database free storage is low"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = module.database.instance_id
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "ecs_cpu_api" {
  alarm_name          = "${var.environment}-plue-api-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "90"
  alarm_description   = "API server CPU utilization is high"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ServiceName = module.api_server.service_name
    ClusterName = module.ecs_cluster.cluster_name
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "ecs_cpu_web" {
  alarm_name          = "${var.environment}-plue-web-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "90"
  alarm_description   = "Web app CPU utilization is high"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ServiceName = module.web_app.service_name
    ClusterName = module.ecs_cluster.cluster_name
  }

  tags = local.tags
}

# Database Migration Task Definition
resource "aws_ecs_task_definition" "db_migrate" {
  family                   = "${var.environment}-plue-db-migrate"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = module.api_server.task_execution_role_arn

  container_definitions = jsonencode([
    {
      name  = "migrate"
      image = "python:3.12-alpine"
      
      command = ["sh", "-c", "pip install psycopg2-binary && python /app/scripts/migrate.py up"]
      
      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = "${module.database.connection_secret_arn}:url::"
        }
      ]
      
      mountPoints = [
        {
          sourceVolume  = "scripts"
          containerPath = "/app/scripts"
          readOnly      = true
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.environment}/plue-db-migrate"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "migrate"
        }
      }
      
      essential = true
    }
  ])

  volume {
    name = "scripts"

    efs_volume_configuration {
      file_system_id     = module.storage.file_system_id
      transit_encryption = "ENABLED"
      root_directory     = "/scripts"
    }
  }

  tags = local.tags
}

# CloudWatch Log Group for migrations
resource "aws_cloudwatch_log_group" "db_migrate" {
  name              = "/ecs/${var.environment}/plue-db-migrate"
  retention_in_days = 7

  tags = local.tags
}