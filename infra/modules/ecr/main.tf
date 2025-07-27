# ECR Repository for API Server
resource "aws_ecr_repository" "api_server" {
  name                 = "${var.environment}-plue-api-server"
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-plue-api-server"
  })
}

# ECR Repository for Web App
resource "aws_ecr_repository" "web_app" {
  name                 = "${var.environment}-plue-web-app"
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-plue-web-app"
  })
}

# Lifecycle policy for API Server (keep last 10 images)
resource "aws_ecr_lifecycle_policy" "api_server" {
  repository = aws_ecr_repository.api_server.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Lifecycle policy for Web App (keep last 10 images)
resource "aws_ecr_lifecycle_policy" "web_app" {
  repository = aws_ecr_repository.web_app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}