terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    # Backend configuration will be set via -backend-config
    # bucket         = "terraform-state-<account>-<region>"
    # key            = "aws-cloud-iac/terraform.tfstate"
    # region         = "<region>"
    # dynamodb_table = "terraform-state-lock"
    # encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "Cloud-IaC"
      Owner       = "VarunN"
      Environment = terraform.workspace
      CostCenter  = "R&D"
      ManagedBy   = "Terraform"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC Module
module "vpc" {
  source = "../../modules/vpc"
  
  vpc_cidr             = var.vpc_cidr
  environment          = terraform.workspace
  availability_zones   = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway
}

# S3 Module
module "s3" {
  source = "../../modules/s3"
  
  environment     = terraform.workspace
  account_id      = data.aws_caller_identity.current.account_id
  region          = data.aws_region.current.name
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnet_ids
}

# RDS Module
module "rds" {
  source = "../../modules/rds"
  
  environment        = terraform.workspace
  vpc_id            = module.vpc.vpc_id
  private_subnets   = module.vpc.private_subnet_ids
  vpc_cidr          = module.vpc.vpc_cidr
  db_name           = var.db_name
  db_username       = var.db_username
  db_password       = var.db_password
  instance_class    = var.rds_instance_class
  allocated_storage = var.rds_allocated_storage
  multi_az          = terraform.workspace == "prod" ? true : false
  backup_retention  = terraform.workspace == "prod" ? 30 : 7
  deletion_protection = terraform.workspace == "prod" ? true : false
}

# Application Load Balancer Module
module "alb" {
  source = "../../modules/alb"
  
  environment      = terraform.workspace
  vpc_id          = module.vpc.vpc_id
  public_subnets  = module.vpc.public_subnet_ids
  vpc_cidr        = module.vpc.vpc_cidr
  logs_bucket     = module.s3.logs_bucket_name
  health_check_path = "/healthz"
}

# EC2 Auto Scaling Group Module
module "ec2_asg" {
  source = "../../modules/ec2_asg"
  
  environment        = terraform.workspace
  vpc_id            = module.vpc.vpc_id
  private_subnets   = module.vpc.private_subnet_ids
  target_group_arns = [module.alb.target_group_arn]
  vpc_cidr          = module.vpc.vpc_cidr
  alb_security_group_id = module.alb.security_group_id
  instance_type     = var.ec2_instance_type
  min_size          = var.asg_min_size
  max_size          = var.asg_max_size
  desired_capacity  = var.asg_desired_capacity
  db_endpoint       = module.rds.db_endpoint
  db_name           = var.db_name
  db_username       = var.db_username
  db_password       = var.db_password
  app_image_uri     = var.app_image_uri
}

# CloudWatch Monitoring Module
module "monitoring" {
  source = "../../modules/cw_monitoring"
  
  environment      = terraform.workspace
  alb_arn_suffix  = module.alb.alb_arn_suffix
  asg_name        = module.ec2_asg.asg_name
  rds_instance_id = module.rds.db_instance_id
  logs_bucket     = module.s3.logs_bucket_name
  artifacts_bucket = module.s3.artifacts_bucket_name
  data_bucket     = module.s3.data_bucket_name
} 