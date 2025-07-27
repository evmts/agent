# Security Group for ALB
resource "aws_security_group" "alb" {
  name        = "${var.environment}-plue-alb-sg"
  description = "Security group for Plue Application Load Balancer"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from anywhere"
  }

  dynamic "ingress" {
    for_each = var.enable_https ? [1] : []
    content {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = "HTTPS from anywhere"
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-plue-alb-sg"
  })
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.environment}-plue-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids

  enable_deletion_protection = var.enable_deletion_protection
  enable_http2              = true

  tags = merge(var.tags, {
    Name = "${var.environment}-plue-alb"
  })
}

# Target Group for API Server
resource "aws_lb_target_group" "api_server" {
  name     = "${var.environment}-plue-api-tg"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  deregistration_delay = 30

  tags = merge(var.tags, {
    Name = "${var.environment}-plue-api-tg"
  })
}

# Target Group for Web App
resource "aws_lb_target_group" "web_app" {
  name     = "${var.environment}-plue-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  deregistration_delay = 30

  tags = merge(var.tags, {
    Name = "${var.environment}-plue-web-tg"
  })
}

# HTTP Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = var.enable_https ? "redirect" : "forward"
    
    # Redirect to HTTPS if enabled
    dynamic "redirect" {
      for_each = var.enable_https ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    
    # Forward to web app if HTTPS is not enabled
    target_group_arn = var.enable_https ? null : aws_lb_target_group.web_app.arn
  }
}

# HTTPS Listener (optional)
resource "aws_lb_listener" "https" {
  count = var.enable_https ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_app.arn
  }
}

# Listener Rules for API routing (HTTP)
resource "aws_lb_listener_rule" "api_http" {
  count = var.enable_https ? 0 : 1

  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_server.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

# Listener Rules for API routing (HTTPS)
resource "aws_lb_listener_rule" "api_https" {
  count = var.enable_https ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_server.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

# CloudWatch Alarms for ALB
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts_api" {
  alarm_name          = "${var.environment}-plue-alb-unhealthy-api"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = "0"
  alarm_description   = "This metric monitors unhealthy API server instances"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.api_server.arn_suffix
    LoadBalancer = aws_lb.main.arn_suffix
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts_web" {
  alarm_name          = "${var.environment}-plue-alb-unhealthy-web"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = "0"
  alarm_description   = "This metric monitors unhealthy web app instances"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TargetGroup  = aws_lb_target_group.web_app.arn_suffix
    LoadBalancer = aws_lb.main.arn_suffix
  }

  tags = var.tags
}