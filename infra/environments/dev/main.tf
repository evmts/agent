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
  
  # Cost optimization for dev - single NAT gateway
  enable_nat_gateway = true
  single_nat_gateway = true
  
  tags = local.tags
}

# ECS Cluster
module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  environment               = var.environment
  enable_container_insights = false # Cost optimization for dev
  
  tags = local.tags
}

# ECR Repositories
module "ecr" {
  source = "../../modules/ecr"

  environment          = var.environment
  image_tag_mutability = "MUTABLE"
  scan_on_push        = false # Cost optimization for dev
  
  tags = local.tags
}

# Database
module "database" {
  source = "../../modules/database"

  environment     = var.environment
  vpc_id          = module.network.vpc_id
  subnet_ids      = module.network.private_subnet_ids
  
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  max_allocated_storage   = 40
  backup_retention_period = 3
  multi_az               = false # Cost optimization for dev
  deletion_protection    = false
  skip_final_snapshot    = true
  
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
  enable_deletion_protection = false
  
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
  
  cpu           = "256"
  memory        = "512"
  desired_count = 1
  min_capacity  = 1
  max_capacity  = 2
  
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
  
  cpu           = "256"
  memory        = "512"
  desired_count = 1
  min_capacity  = 1
  max_capacity  = 2
  
  api_endpoint = "http://${module.load_balancer.alb_dns_name}/api"
  load_balancer_target_group_arn = module.load_balancer.web_target_group_arn
  
  tags = local.tags
}

# Security Group Rules to allow API server to access database and storage
resource "aws_security_group_rule" "database_from_api" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = module.api_server.security_group_id
  security_group_id        = module.database.security_group_id
}

resource "aws_security_group_rule" "efs_from_api" {
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = module.api_server.security_group_id
  security_group_id        = module.storage.security_group_id
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
  retention_in_days = 3

  tags = local.tags
}