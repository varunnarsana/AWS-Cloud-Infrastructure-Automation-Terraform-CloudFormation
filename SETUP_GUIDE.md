# AWS Cloud Infrastructure Automation - Setup Guide

## 🎯 Project Overview

This project demonstrates a production-grade AWS infrastructure built with **Terraform** and **CloudFormation**, showcasing:

- **Infrastructure as Code (IaC)** best practices
- **Multi-environment** deployment (dev/prod)
- **CI/CD automation** with GitHub Actions
- **Security-first** approach with private subnets and least-privilege access
- **Cost optimization** with lifecycle policies and budget monitoring
- **Comprehensive monitoring** with CloudWatch and SNS alerts

## 🏗️ Architecture Components

### Core Infrastructure (Terraform)
- **VPC**: Multi-AZ with public/private subnets
- **Networking**: Internet Gateway, NAT Gateways, route tables
- **Compute**: EC2 Auto Scaling Group with launch templates
- **Database**: RDS PostgreSQL Multi-AZ
- **Storage**: S3 buckets for logs, artifacts, and data
- **Load Balancing**: Application Load Balancer with health checks
- **Monitoring**: CloudWatch dashboards, alarms, and SNS topics

### Application Layer (CloudFormation)
- **IAM Roles**: EC2 instance profile, Lambda execution, deployment
- **Lambda Function**: "Bucket Guardian" for S3 validation
- **EventBridge Rules**: Scheduled and event-driven triggers
- **SNS Topics**: Alerting and notifications

### Application
- **Flask API**: Containerized application with health endpoints
- **Docker**: Automated containerization and deployment
- **Health Checks**: `/healthz` endpoint for load balancer

## 🚀 Quick Start

### Prerequisites
1. **AWS CLI** configured with appropriate permissions
2. **Terraform** >= 1.0 installed
3. **GitHub repository** with GitHub Actions enabled
4. **AWS account** with sufficient permissions

### 1. Repository Setup
```bash
# Clone the repository
git clone <your-repo-url>
cd aws-cloud-iac

# Set up GitHub secrets (required for CI/CD)
# Go to Settings > Secrets and variables > Actions
# Add the following secrets:
# - AWS_ACCESS_KEY_ID
# - AWS_SECRET_ACCESS_KEY
# - AWS_REGION
# - TF_STATE_BUCKET (S3 bucket for Terraform state)
# - TF_STATE_TABLE (DynamoDB table for state locking)
# - DB_PASSWORD (Database password)
```

### 2. Infrastructure Deployment

#### Option A: Manual Deployment
```bash
# Navigate to Terraform directory
cd terraform/stacks/main

# Initialize Terraform
terraform init

# Select/create workspace
terraform workspace select dev
# or
terraform workspace new dev

# Plan deployment
terraform plan -var="db_password=your_password"

# Apply deployment
terraform apply -var="db_password=your_password"
```

#### Option B: Automated CI/CD
1. Push changes to `main` branch
2. GitHub Actions will automatically:
   - Validate and lint Terraform code
   - Deploy to dev environment
   - Deploy to prod environment (with manual approval)

### 3. CloudFormation Deployment
```bash
# Deploy IAM, Lambda, and EventBridge resources
aws cloudformation deploy \
  --template-file cloudformation/iam-lambda-eventbridge.yaml \
  --stack-name iam-lambda-eventbridge-dev \
  --parameter-overrides file://cloudformation/parameters-dev.json \
  --capabilities CAPABILITY_NAMED_IAM
```

### 4. Verification
```bash
# Run smoke tests
./scripts/smoke-test.sh dev us-east-1

# Run full demo
./scripts/demo.sh dev us-east-1
```

## 🔧 Configuration

### Environment Variables
- `ENVIRONMENT`: dev/prod
- `AWS_REGION`: AWS region for deployment
- `DB_PASSWORD`: Database password (sensitive)

### Terraform Variables
- `vpc_cidr`: VPC CIDR block (default: 10.0.0.0/16)
- `instance_type`: EC2 instance type (default: t3.small)
- `asg_min_size`: Auto Scaling Group minimum size (default: 2)
- `asg_max_size`: Auto Scaling Group maximum size (default: 4)

### CloudFormation Parameters
- `Environment`: Environment name
- `S3LogsBucket`: S3 bucket for logs
- `S3ArtifactsBucket`: S3 bucket for artifacts
- `S3DataBucket`: S3 bucket for data
- `SNSTopicArn`: SNS topic ARN for alerts

## 📊 Monitoring & Alerting

### CloudWatch Dashboards
- **ALB Metrics**: Request count, response time, error rates
- **EC2 Metrics**: CPU utilization, memory usage
- **RDS Metrics**: CPU, connections, storage
- **S3 Metrics**: Bucket size, object count

### CloudWatch Alarms
- **High CPU**: Scale up when CPU > 70%
- **Low CPU**: Scale down when CPU < 30%
- **RDS Storage**: Alert when free storage < 1GB
- **ALB Errors**: Alert when 5XX errors > 5/min

### SNS Notifications
- Email alerts for critical issues
- Budget threshold notifications
- Infrastructure health updates

## 🔒 Security Features

### Network Security
- **Private subnets** for compute and database
- **Security groups** with least-privilege access
- **NACLs** for additional network control
- **VPC endpoints** for AWS services

### Data Security
- **S3 encryption** at rest (AES-256)
- **RDS encryption** with KMS
- **Public access blocked** on S3 buckets
- **IAM roles** with minimal permissions

### Access Control
- **SSM Parameter Store** for secrets
- **No SSH keys** in code
- **Session Manager** for instance access
- **CloudTrail** for API logging

## 💰 Cost Optimization

### Resource Optimization
- **Auto Scaling** based on demand
- **S3 lifecycle policies** to cheaper storage tiers
- **NAT Gateway strategy** (single vs. multiple)
- **Instance scheduling** for non-production

### Budget Management
- **AWS Budgets** with monthly limits
- **Cost alerts** at 80% and 100%
- **Resource tagging** for cost allocation
- **Regular cost reviews** and optimization

## 🧪 Testing & Validation

### Smoke Tests
```bash
# Test all infrastructure components
./scripts/smoke-test.sh dev us-east-1
```

### Application Tests
```bash
# Test application endpoints
curl http://<alb-dns-name>/healthz
curl http://<alb-dns-name>/api/status
```

### Infrastructure Tests
```bash
# Test auto scaling
aws autoscaling describe-auto-scaling-groups

# Test monitoring
aws cloudwatch describe-dashboards

# Test Lambda
aws lambda invoke --function-name dev-bucket-guardian
```

## 🚨 Troubleshooting

### Common Issues

#### Terraform State Issues
```bash
# Reinitialize backend
terraform init -reconfigure

# Check workspace
terraform workspace list
terraform workspace select dev
```

#### Application Health Issues
```bash
# Check EC2 instance logs
aws logs describe-log-groups
aws logs tail /aws/ec2/dev-app

# Check ALB target health
aws elbv2 describe-target-health
```

#### Database Connection Issues
```bash
# Verify security groups
aws ec2 describe-security-groups

# Check RDS status
aws rds describe-db-instances
```

### Debug Commands
```bash
# Check infrastructure status
terraform show
terraform output

# Check CloudFormation stack
aws cloudformation describe-stacks

# Check Lambda function
aws lambda get-function --function-name dev-bucket-guardian
```

## 🔄 CI/CD Pipeline

### GitHub Actions Workflows

#### Terraform CI/CD
- **Validation**: Format, lint, security scan
- **Planning**: Generate and comment plan on PRs
- **Deployment**: Auto-deploy to dev, manual approval for prod

#### CloudFormation CI/CD
- **Validation**: Template validation and linting
- **Deployment**: Automated stack deployment
- **Testing**: Lambda function testing

### Deployment Strategy
1. **Development**: Automatic deployment on merge to main
2. **Production**: Manual approval required
3. **Rollback**: Automatic rollback on failure
4. **State Management**: S3 backend with DynamoDB locking

## 📚 Learning Resources

### Documentation
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS CloudFormation](https://docs.aws.amazon.com/cloudformation/)
- [GitHub Actions](https://docs.github.com/en/actions)

### Best Practices
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/)
- [Infrastructure as Code](https://www.hashicorp.com/resources/infrastructure-as-code)

## 🤝 Contributing

### Development Workflow
1. Create feature branch
2. Make changes with proper testing
3. Run validation locally
4. Submit pull request
5. CI/CD pipeline validates and deploys

### Code Standards
- **Terraform**: Use consistent formatting and naming
- **CloudFormation**: Follow AWS best practices
- **Scripts**: Use proper error handling and logging
- **Documentation**: Keep README and guides updated

## 🧹 Cleanup

### Destroy Infrastructure
```bash
# Destroy Terraform resources
cd terraform/stacks/main
terraform workspace select dev
terraform destroy -auto-approve

# Delete CloudFormation stack
aws cloudformation delete-stack --stack-name iam-lambda-eventbridge-dev

# Clean up S3 buckets (after lifecycle policies complete)
aws s3 rb s3://app-logs-dev-<account> --force
aws s3 rb s3://app-artifacts-dev-<account> --force
aws s3 rb s3://app-data-dev-<account> --force
```

### Cost Monitoring
- Monitor AWS billing dashboard
- Check for orphaned resources
- Verify all resources are properly terminated

## 📋 Evaluation Checklist

### Infrastructure as Code ✅
- [ ] Terraform builds VPC, EC2/ASG, RDS, S3, ALB, IAM, CloudWatch
- [ ] CloudFormation builds IAM roles, Lambda, EventBridge
- [ ] Modular design with reusable components
- [ ] Environment-specific configurations

### CI/CD & Automation ✅
- [ ] GitHub Actions workflows for Terraform and CloudFormation
- [ ] Automated testing and validation
- [ ] Production deployment gating
- [ ] State management with S3 backend

### Security & Compliance ✅
- [ ] Private subnets for sensitive resources
- [ ] Least-privilege IAM policies
- [ ] S3 public access blocked
- [ ] Secrets management via SSM
- [ ] Security groups with minimal access

### Monitoring & Operations ✅
- [ ] CloudWatch alarms and SNS notifications
- [ ] Application and infrastructure logging
- [ ] Health checks and auto-healing
- [ ] Cost monitoring and budgets

### Documentation ✅
- [ ] Clear architecture diagrams
- [ ] Setup and deployment instructions
- [ ] Runbook for common operations
- [ ] Demo scripts for validation

## 🎉 Success!

You've successfully deployed a production-grade AWS infrastructure that demonstrates:

- **Professional DevOps skills** with modern tools
- **Security best practices** implementation
- **Cost optimization** strategies
- **Monitoring and alerting** setup
- **CI/CD automation** workflows

This project showcases the skills that hiring managers look for in DevOps engineers and cloud architects. Use it as a portfolio piece and customize it for your specific needs!

---

**Note**: This infrastructure is designed for learning and demonstration. Always review security configurations before deploying to production environments. 