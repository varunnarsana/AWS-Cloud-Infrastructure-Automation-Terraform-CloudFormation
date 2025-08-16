variable "environment" {
  description = "Environment name (dev, prod, etc.)"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ARN suffix of the Application Load Balancer"
  type        = string
}

variable "asg_name" {
  description = "Name of the Auto Scaling Group"
  type        = string
}

variable "rds_instance_id" {
  description = "ID of the RDS instance"
  type        = string
}

variable "logs_bucket" {
  description = "Name of the S3 logs bucket"
  type        = string
}

variable "artifacts_bucket" {
  description = "Name of the S3 artifacts bucket"
  type        = string
}

variable "data_bucket" {
  description = "Name of the S3 data bucket"
  type        = string
} 