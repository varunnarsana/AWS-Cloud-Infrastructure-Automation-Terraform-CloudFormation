# AWS Cloud Infrastructure Automation (Terraform + CloudFormation)

A production-grade, multi-AZ AWS foundation using Terraform for core infrastructure and CloudFormation for IAM, Lambda, and EventBridge components. This project demonstrates end-to-end infrastructure automation with CI/CD, security, monitoring, and cost guardrails.

## Project Goals

- **Design, automate, and operate cloud infrastructure with Infrastructure as Code (IaC)**
- **Hands-on experience** with VPC, EC2, RDS, S3, IAM, CloudWatch, EventBridge, CloudFormation, Terraform, and GitHub Actions for CI/CD
- **Understand security, high availability, cost control, and observability** principles
- **Implement production-ready patterns** for cloud infrastructure

## Target Architecture

### High-Level Overview
- **VPC** (10.0.0.0/16) with 2 public and 2 private subnets across 2 AZs
- **Internet Gateway + NAT Gateway(s)** (one per AZ; optionally 1 NAT for cost optimization)
- **Application Load Balancer (ALB)** in public subnets
- **EC2 Auto Scaling Group** in private subnets running a simple Flask API
- **Amazon RDS (PostgreSQL)** multi-AZ in private subnets
- **S3 buckets** for logs, artifacts, and data with lifecycle policies
- **CloudWatch** monitoring with alarms and SNS notifications
- **CloudFormation stack** for IAM roles, Lambda functions, and EventBridge rules

### Network Architecture
```
Internet
    ↓
Internet Gateway
    ↓
Public Subnets (AZ-a, AZ-b)
    ↓
Application Load Balancer
    ↓
Private Subnets (AZ-a, AZ-b)
    ↓
EC2 Auto Scaling Group + RDS
```

## Quick Start

### Prerequisites
- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- Docker
- Python 3.11+

### Environment Setup
1. **Configure AWS credentials:**
   ```bash
   aws configure
   ```

2. **Initialize Terraform backend:**
   ```bash
   cd terraform/stacks/main
   terraform init
   ```

3. **Deploy infrastructure:**
   ```bash
   # For dev environment
   terraform workspace select dev
   terraform plan
   terraform apply
   
   # For prod environment
   terraform workspace select prod
   terraform plan
   terraform apply
   ```

4. **Deploy CloudFormation stack:**
   ```bash
   aws cloudformation deploy \
     --template-file cloudformation/iam-lambda-eventbridge.yaml \
     --stack-name iam-lambda-eventbridge \
     --parameter-overrides file://cloudformation/parameters-dev.json
   ```

## Repository Structure

```
aws-cloud-iac/
├─ README.md                           # This file
├─ diagrams/                           # Architecture diagrams
│  └─ architecture.drawio
├─ app/                               # Minimal Flask API (Dockerized)
│  ├─ Dockerfile
│  └─ src/
├─ terraform/                         # Terraform infrastructure
│  ├─ envs/                          # Environment-specific configs
│  │  ├─ dev/
│  │  └─ prod/
│  ├─ modules/                       # Reusable Terraform modules
│  │  ├─ vpc/
│  │  ├─ alb/
│  │  ├─ ec2_asg/
│  │  ├─ rds/
│  │  ├─ s3/
│  │  └─ cw_monitoring/
│  └─ stacks/                        # Main Terraform stack
│     └─ main/
├─ cloudformation/                    # CloudFormation templates
│  ├─ iam-lambda-eventbridge.yaml
│  └─ parameters-dev.json
├─ .github/workflows/                 # CI/CD pipelines
│  ├─ terraform-ci.yml
│  └─ cloudformation-ci.yml
└─ scripts/                          # Utility scripts
   ├─ bootstrap-ec2.sh
   └─ smoke-test.sh
```

## Core Components

### 1. Terraform Infrastructure
- **VPC Module**: Creates VPC with public/private subnets, route tables, and NAT gateways
- **ALB Module**: Application Load Balancer with target groups and listeners
- **EC2 ASG Module**: Auto Scaling Group with launch templates and scaling policies
- **RDS Module**: Multi-AZ PostgreSQL database with encryption and backups
- **S3 Module**: Three buckets (logs, artifacts, data) with lifecycle policies
- **CloudWatch Module**: Monitoring, alarms, and SNS notifications

### 2.CloudFormation Stack
- **IAM Roles**: EC2 instance profile, Lambda execution, and deployment roles
- **Lambda Function**: "Bucket Guardian" for S3 lifecycle validation and enforcement
- **EventBridge Rules**: Scheduled and event-driven Lambda triggers
- **SNS Topic**: Alerting and notifications

### 3. Application
- **Flask API**: Simple health check endpoint (/healthz)
- **Docker Container**: Containerized application with health monitoring
- **User Data Script**: Bootstrap script for EC2 instances

## Security Features

- **Private subnets** for compute and database resources
- **Security Groups** with least-privilege access
- **S3 buckets** with public access blocked and encryption at rest
- **SSM Parameter Store** for secure credential storage
- **IAM roles** with minimal required permissions
- **VPC endpoints** for AWS services (optional)

## Cost Optimization

- **AWS Budgets** with alerts for cost thresholds
- **S3 lifecycle policies** to transition data to cheaper storage tiers
- **NAT Gateway strategy** (one per AZ vs. single NAT for cost)
- **Auto Scaling** to right-size compute resources
- **RDS instance scheduling** for non-production environments

## Monitoring & Observability

- **CloudWatch Logs** for application and infrastructure logs
- **Custom metrics** for application performance
- **Alarms** for CPU, storage, and error rates
- **SNS notifications** for critical alerts
- **Dashboards** for operational visibility

## CI/CD Pipeline

### GitHub Actions Workflows
1. **Terraform CI**: Format, validate, lint, plan, and apply infrastructure changes
2. **CloudFormation CI**: Deploy IAM, Lambda, and EventBridge components
3. **Application CI**: Build and deploy Docker images to ECR

### Deployment Strategy
- **Dev**: Automatic deployment on merge to main
- **Prod**: Manual approval required before deployment
- **State Management**: S3 backend with DynamoDB locking

## Testing & Validation

### Smoke Tests
- Health check endpoint verification
- Database connectivity tests
- S3 bucket access validation
- Lambda function execution tests

### Failover Testing
- EC2 instance termination to verify ASG self-healing
- RDS failover testing
- ALB health check validation

## 🗑Cleanup

### Destroy Infrastructure
```bash
# Destroy Terraform resources
terraform destroy

# Delete CloudFormation stack
aws cloudformation delete-stack --stack-name iam-lambda-eventbridge

# Clean up S3 buckets (after lifecycle policies complete)
aws s3 rb s3://app-logs-dev-<account> --force
aws s3 rb s3://app-artifacts-dev-<account> --force
aws s3 rb s3://app-data-dev-<account> --force
```

## Evaluation Checklist

### Infrastructure as Code
- [ ] Terraform builds VPC, EC2/ASG, RDS, S3, ALB, IAM, CloudWatch
- [ ] CloudFormation builds IAM roles, Lambda, EventBridge
- [ ] Modular design with reusable components
- [ ] Environment-specific configurations

### CI/CD & Automation
- [ ] GitHub Actions workflows for Terraform and CloudFormation
- [ ] Automated testing and validation
- [ ] Production deployment gating
- [ ] State management with S3 backend

### Security & Compliance
- [ ] Private subnets for sensitive resources
- [ ] Least-privilege IAM policies
- [ ] S3 public access blocked
- [ ] Secrets management via SSM
- [ ] Security groups with minimal access

### Monitoring & Operations
- [ ] CloudWatch alarms and SNS notifications
- [ ] Application and infrastructure logging
- [ ] Health checks and auto-healing
- [ ] Cost monitoring and budgets

### Documentation
- [ ] Clear architecture diagrams
- [ ] Setup and deployment instructions
- [ ] Runbook for common operations
- [ ] Demo scripts for validation

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests and validation
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For questions or issues:
1. Check the troubleshooting section in this README
2. Review the architecture diagrams
3. Check CloudWatch logs and CloudTrail
4. Open an issue in the repository

---

**Note**: This project is designed for learning and demonstration purposes. Always review and customize security configurations before deploying to production environments. 
