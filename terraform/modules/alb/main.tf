# Security Group for ALB
resource "aws_security_group" "alb" {
  name_prefix = "${var.environment}-alb-sg"
  vpc_id      = var.vpc_id
  
  description = "Security group for Application Load Balancer"
  
  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "HTTPS from Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${var.environment}-alb-sg"
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnets
  
  enable_deletion_protection = false
  
  access_logs {
    bucket  = var.logs_bucket
    prefix  = "alb-logs"
    enabled = true
  }
  
  tags = {
    Name = "${var.environment}-alb"
  }
}

# Target Group for the application
resource "aws_lb_target_group" "main" {
  name     = "${var.environment}-app-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = var.health_check_path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }
  
  tags = {
    Name = "${var.environment}-app-tg"
  }
}

# HTTP Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
  
  tags = {
    Name = "${var.environment}-http-listener"
  }
}

# HTTPS Listener (redirect to HTTP for now, can be enhanced with ACM)
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = null # Add ACM certificate ARN when available
  
  default_action {
    type = "redirect"
    
    redirect {
      port        = "80"
      protocol    = "HTTP"
      status_code = "HTTP_301"
    }
  }
  
  tags = {
    Name = "${var.environment}-https-listener"
  }
}

# IAM policy for ALB to write logs to S3
resource "aws_iam_policy" "alb_logging" {
  name        = "${var.environment}-alb-logging-policy"
  description = "Policy for ALB to write access logs to S3"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::${var.logs_bucket}/alb-logs/*"
      }
    ]
  })
} 