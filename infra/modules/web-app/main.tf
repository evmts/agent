# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "web_app" {
  name              = "/ecs/${var.environment}/plue-web-app"
  retention_in_days = 7

  tags = var.tags
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "task_execution" {
  name = "${var.environment}-plue-web-app-task-execution"

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

# IAM Role for ECS Task
resource "aws_iam_role" "task" {
  name = "${var.environment}-plue-web-app-task"

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

# Security Group for Web App
resource "aws_security_group" "web_app" {
  name        = "${var.environment}-plue-web-app-sg"
  description = "Security group for Plue web app"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
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
    Name = "${var.environment}-plue-web-app-sg"
  })
}

# ECS Task Definition
resource "aws_ecs_task_definition" "web_app" {
  family                   = "${var.environment}-plue-web-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn           = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name  = "web-app"
      image = "${var.ecr_repository_url}:${var.image_tag}"
      
      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]
      
      environment = [
        {
          name  = "API_ENDPOINT"
          value = var.api_endpoint
        }
      ]
      
      healthCheck = {
        command     = ["CMD-SHELL", "wget -q -O - http://127.0.0.1/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.web_app.name
          "awslogs-region"        = data.aws_region.current.id
          "awslogs-stream-prefix" = "ecs"
        }
      }
      
      essential = true
    }
  ])

  tags = var.tags
}

# ECS Service
resource "aws_ecs_service" "web_app" {
  name            = "${var.environment}-plue-web-app"
  cluster         = var.ecs_cluster_id
  task_definition = aws_ecs_task_definition.web_app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  
  platform_version = "LATEST"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.web_app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.load_balancer_target_group_arn
    container_name   = "web-app"
    container_port   = 80
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  tags = var.tags

  depends_on = [aws_iam_role_policy_attachment.task_execution]
}

# Auto Scaling Target
resource "aws_appautoscaling_target" "web_app" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${var.ecs_cluster_id}/${aws_ecs_service.web_app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Auto Scaling Policy - CPU
resource "aws_appautoscaling_policy" "web_app_cpu" {
  name               = "${var.environment}-plue-web-app-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.web_app.resource_id
  scalable_dimension = aws_appautoscaling_target.web_app.scalable_dimension
  service_namespace  = aws_appautoscaling_target.web_app.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 75.0
  }
}

# Auto Scaling Policy - Memory
resource "aws_appautoscaling_policy" "web_app_memory" {
  name               = "${var.environment}-plue-web-app-memory"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.web_app.resource_id
  scalable_dimension = aws_appautoscaling_target.web_app.scalable_dimension
  service_namespace  = aws_appautoscaling_target.web_app.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value = 75.0
  }
}

data "aws_region" "current" {}