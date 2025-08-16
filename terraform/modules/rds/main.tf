# Security Group for RDS
resource "aws_security_group" "rds" {
  name_prefix = "${var.environment}-rds-sg"
  vpc_id      = var.vpc_id
  
  description = "Security group for RDS PostgreSQL database"
  
  ingress {
    description = "PostgreSQL from application instances"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${var.environment}-rds-sg"
  }
}

# Subnet Group for RDS
resource "aws_db_subnet_group" "main" {
  name       = "${var.environment}-rds-subnet-group"
  subnet_ids = var.private_subnets
  
  tags = {
    Name = "${var.environment}-rds-subnet-group"
  }
}

# Parameter Group for PostgreSQL
resource "aws_db_parameter_group" "main" {
  family = "postgres15"
  name   = "${var.environment}-postgres15-params"
  
  parameter {
    name  = "log_connections"
    value = "1"
  }
  
  parameter {
    name  = "log_disconnections"
    value = "1"
  }
  
  parameter {
    name  = "log_statement"
    value = "all"
  }
  
  tags = {
    Name = "${var.environment}-postgres15-params"
  }
}

# Option Group for PostgreSQL
resource "aws_db_option_group" "main" {
  name                     = "${var.environment}-postgres15-options"
  engine_name              = "postgres"
  major_engine_version     = "15"
  
  tags = {
    Name = "${var.environment}-postgres15-options"
  }
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier = "${var.environment}-postgres-db"
  
  # Engine configuration
  engine               = "postgres"
  engine_version       = "15.4"
  instance_class       = var.instance_class
  allocated_storage    = var.allocated_storage
  max_allocated_storage = var.allocated_storage * 2
  
  # Database configuration
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 5432
  
  # Network configuration
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name
  
  # Storage configuration
  storage_type          = "gp2"
  storage_encrypted     = true
  kms_key_id            = null # Use default AWS managed key
  
  # Backup configuration
  backup_retention_period = var.backup_retention
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  # High availability
  multi_az = var.multi_az
  
  # Performance insights
  performance_insights_enabled = true
  performance_insights_retention_period = 7
  
  # Monitoring
  monitoring_interval = 60
  monitoring_role_arn = null # Use default monitoring role
  
  # Deletion protection
  deletion_protection = var.deletion_protection
  skip_final_snapshot = false
  final_snapshot_identifier = "${var.environment}-postgres-final-snapshot"
  
  # Parameter and option groups
  parameter_group_name = aws_db_parameter_group.main.name
  option_group_name    = aws_db_option_group.main.name
  
  # Tags
  tags = {
    Name = "${var.environment}-postgres-db"
  }
}

# CloudWatch Log Group for RDS
resource "aws_cloudwatch_log_group" "rds" {
  name              = "/aws/rds/instance/${aws_db_instance.main.identifier}"
  retention_in_days = 30
  
  tags = {
    Name = "${var.environment}-rds-logs"
  }
}

# RDS Enhanced Monitoring
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.environment}-rds-monitoring-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })
  
  tags = {
    Name = "${var.environment}-rds-monitoring-role"
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
} 