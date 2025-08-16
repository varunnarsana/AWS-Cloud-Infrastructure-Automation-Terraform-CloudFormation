# SNS Topic for alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.environment}-alerts"
  
  tags = {
    Name = "${var.environment}-alerts"
  }
}

# SNS Topic Subscription (email)
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "admin@example.com" # Change this to your email
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "app" {
  name              = "/aws/ec2/${var.environment}-app"
  retention_in_days = 30
  
  tags = {
    Name = "${var.environment}-app-logs"
  }
}

resource "aws_cloudwatch_log_group" "alb" {
  name              = "/aws/applicationloadbalancer/${var.environment}-alb"
  retention_in_days = 30
  
  tags = {
    Name = "${var.environment}-alb-logs"
  }
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.environment}-bucket-guardian"
  retention_in_days = 30
  
  tags = {
    Name = "${var.environment}-lambda-logs"
  }
}

# CloudWatch Alarms

# ALB 5XX Error Rate Alarm
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.environment}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
  
  alarm_description = "ALB 5XX errors > 5 per 5 minutes"
  alarm_actions     = [aws_sns_topic.alerts.arn]
  
  tags = {
    Name = "${var.environment}-alb-5xx-alarm"
  }
}

# ALB Target Response Time Alarm
resource "aws_cloudwatch_metric_alarm" "alb_response_time" {
  alarm_name          = "${var.environment}-alb-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "300"
  statistic           = "Average"
  threshold           = "2"
  
  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
  
  alarm_description = "ALB target response time > 2 seconds"
  alarm_actions     = [aws_sns_topic.alerts.arn]
  
  tags = {
    Name = "${var.environment}-alb-response-time-alarm"
  }
}

# RDS Free Storage Space Alarm
resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${var.environment}-rds-free-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "1073741824" # 1 GB in bytes
  
  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }
  
  alarm_description = "RDS free storage space < 1 GB"
  alarm_actions     = [aws_sns_topic.alerts.arn]
  
  tags = {
    Name = "${var.environment}-rds-storage-alarm"
  }
}

# RDS CPU Utilization Alarm
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.environment}-rds-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  
  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }
  
  alarm_description = "RDS CPU utilization > 80%"
  alarm_actions     = [aws_sns_topic.alerts.arn]
  
  tags = {
    Name = "${var.environment}-rds-cpu-alarm"
  }
}

# S3 Bucket Size Alarm
resource "aws_cloudwatch_metric_alarm" "s3_bucket_size" {
  alarm_name          = "${var.environment}-s3-bucket-size"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "BucketSizeBytes"
  namespace           = "AWS/S3"
  period              = "86400" # 24 hours
  statistic           = "Average"
  threshold           = "107374182400" # 100 GB in bytes
  
  dimensions = {
    BucketName = var.data_bucket
    StorageType = "StandardStorage"
  }
  
  alarm_description = "S3 data bucket size > 100 GB"
  alarm_actions     = [aws_sns_topic.alerts.arn]
  
  tags = {
    Name = "${var.environment}-s3-bucket-size-alarm"
  }
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.environment}-infrastructure-dashboard"
  
  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
            [".", "TargetResponseTime", ".", "."],
            [".", "HTTPCode_ELB_5XX_Count", ".", "."]
          ]
          period = 300
          stat   = "Sum"
          region = "us-east-1"
          title  = "ALB Metrics"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.rds_instance_id],
            [".", "DatabaseConnections", ".", "."],
            [".", "FreeStorageSpace", ".", "."]
          ]
          period = 300
          stat   = "Average"
          region = "us-east-1"
          title  = "RDS Metrics"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.asg_name]
          ]
          period = 300
          stat   = "Average"
          region = "us-east-1"
          title  = "EC2 Auto Scaling Group CPU"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        
        properties = {
          metrics = [
            ["AWS/S3", "BucketSizeBytes", "BucketName", var.data_bucket, "StorageType", "StandardStorage"],
            [".", "NumberOfObjects", ".", ".", ".", "."]
          ]
          period = 86400
          stat   = "Average"
          region = "us-east-1"
          title  = "S3 Bucket Metrics"
        }
      }
    ]
  })
}

# AWS Budgets
resource "aws_budgets_budget" "cost" {
  name              = "${var.environment}-monthly-budget"
  budget_type       = "COST"
  limit_amount      = "100"
  limit_unit        = "USD"
  time_period_start = "2024-01-01_00:00"
  time_unit         = "MONTHLY"
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = ["admin@example.com"] # Change this to your email
  }
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = ["admin@example.com"] # Change this to your email
  }
} 