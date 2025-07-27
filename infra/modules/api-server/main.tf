# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "api_server" {
  name              = "/ecs/${var.environment}/plue-api-server"
  retention_in_days = 7

  tags = var.tags
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "task_execution" {
  name = "${var.environment}-plue-api-server-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# Attach AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Additional policy for Secrets Manager access
resource "aws_iam_role_policy" "task_execution_secrets" {
  name = "${var.environment}-plue-api-server-secrets"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [var.database_secret_arn]
      }
    ]
  })
}

# IAM Role for ECS Task
resource "aws_iam_role" "task" {
  name = "${var.environment}-plue-api-server-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# Policy for EFS access
resource "aws_iam_role_policy" "task_efs" {
  name = "${var.environment}-plue-api-server-efs"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite"
        ]
        Resource = "*"
      }
    ]
  })
}

# Security Group for API Server
resource "aws_security_group" "api_server" {
  name        = "${var.environment}-plue-api-server-sg"
  description = "Security group for Plue API server"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-plue-api-server-sg"
  })
}

# ECS Task Definition
resource "aws_ecs_task_definition" "api_server" {
  family                   = "${var.environment}-plue-api-server"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn           = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name  = "api-server"
      image = "${var.ecr_repository_url}:${var.image_tag}"
      
      command = ["server"]
      
      portMappings = [
        {
          containerPort = 8000
          protocol      = "tcp"
        }
      ]
      
      environment = [
        {
          name  = "PORT"
          value = "8000"
        }
      ]
      
      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = "${var.database_secret_arn}:url::"
        }
      ]
      
      mountPoints = [
        {
          sourceVolume  = "git-repos"
          containerPath = "/git-repos"
          readOnly      = false
        }
      ]
      
      healthCheck = {
        command     = ["CMD-SHELL", "wget -q -O - http://127.0.0.1:8000/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.api_server.name
          "awslogs-region"        = data.aws_region.current.id
          "awslogs-stream-prefix" = "ecs"
        }
      }
      
      essential = true
    }
  ])

  volume {
    name = "git-repos"

    efs_volume_configuration {
      file_system_id     = var.efs_file_system_id
      transit_encryption = "ENABLED"
      
      authorization_config {
        access_point_id = var.efs_access_point_id
        iam             = "ENABLED"
      }
    }
  }

  tags = var.tags
}

# ECS Service
resource "aws_ecs_service" "api_server" {
  name            = "${var.environment}-plue-api-server"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.api_server.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  
  platform_version = "LATEST"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.api_server.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.load_balancer_target_group_arn
    container_name   = "api-server"
    container_port   = 8000
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  tags = var.tags

  depends_on = [aws_iam_role_policy_attachment.task_execution]
}

# Auto Scaling Target
resource "aws_appautoscaling_target" "api_server" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${var.ecs_cluster_id}/${aws_ecs_service.api_server.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Auto Scaling Policy - CPU
resource "aws_appautoscaling_policy" "api_server_cpu" {
  name               = "${var.environment}-plue-api-server-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.api_server.resource_id
  scalable_dimension = aws_appautoscaling_target.api_server.scalable_dimension
  service_namespace  = aws_appautoscaling_target.api_server.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 75.0
  }
}

# Auto Scaling Policy - Memory
resource "aws_appautoscaling_policy" "api_server_memory" {
  name               = "${var.environment}-plue-api-server-memory"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.api_server.resource_id
  scalable_dimension = aws_appautoscaling_target.api_server.scalable_dimension
  service_namespace  = aws_appautoscaling_target.api_server.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value = 75.0
  }
}

data "aws_region" "current" {}