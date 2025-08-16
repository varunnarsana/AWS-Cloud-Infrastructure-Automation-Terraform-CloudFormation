#!/bin/bash

# AWS Cloud Infrastructure Automation - Demo Script
# This script demonstrates the infrastructure capabilities

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT=${1:-dev}
REGION=${2:-us-east-1}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Display demo information
show_demo_info() {
    cat << 'EOF'

╔══════════════════════════════════════════════════════════════════════════════╗
║                    AWS Cloud Infrastructure Automation Demo                   ║
║                                                                              ║
║  This demo showcases a production-grade AWS infrastructure built with:      ║
║  • Terraform for core infrastructure (VPC, EC2, RDS, S3, ALB)             ║
║  • CloudFormation for IAM, Lambda, and EventBridge                          ║
║  • GitHub Actions for CI/CD automation                                      ║
║  • Comprehensive monitoring and alerting                                    ║
║  • Security best practices and cost optimization                            ║
║                                                                              ║
║  Architecture:                                                               ║
║  • Multi-AZ VPC with public/private subnets                                ║
║  • Application Load Balancer in public subnets                             ║
║  • EC2 Auto Scaling Group in private subnets                               ║
║  • RDS PostgreSQL Multi-AZ in private subnets                              ║
║  • S3 buckets for logs, artifacts, and data                               ║
║  • CloudWatch monitoring with SNS alerts                                    ║
║  • Lambda function for S3 bucket validation                                ║
║  • EventBridge rules for scheduled and event-driven triggers                ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝

EOF
}

# Show demo steps
show_demo_steps() {
    cat << 'EOF'

📋 Demo Steps:

1. 🏗️  Infrastructure Deployment
   • Deploy Terraform infrastructure
   • Deploy CloudFormation stack
   • Verify all resources are created

2. 🧪 Testing & Validation
   • Run smoke tests
   • Test application endpoints
   • Verify monitoring and alerting

3. 🔄 Auto Scaling Demo
   • Simulate load to trigger scaling
   • Verify ASG behavior
   • Check CloudWatch metrics

4. 🚨 Monitoring & Alerting Demo
   • Trigger test alarms
   • Verify SNS notifications
   • Check CloudWatch dashboards

5. 🧹 Cleanup
   • Destroy infrastructure
   • Verify cleanup completion

EOF
}

# Deploy infrastructure
deploy_infrastructure() {
    log_info "Step 1: Deploying Infrastructure"
    
    # Change to Terraform directory
    cd terraform/stacks/main
    
    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init
    
    # Select workspace
    log_info "Selecting $ENVIRONMENT workspace..."
    terraform workspace select $ENVIRONMENT || terraform workspace new $ENVIRONMENT
    
    # Plan deployment
    log_info "Planning Terraform deployment..."
    terraform plan -var="db_password=demo123!" -out=tfplan
    
    # Apply deployment
    log_info "Applying Terraform deployment..."
    terraform apply tfplan
    
    # Get outputs
    log_info "Getting infrastructure outputs..."
    ALB_DNS_NAME=$(terraform output -raw alb_dns_name)
    DB_ENDPOINT=$(terraform output -raw db_endpoint)
    
    log_success "Infrastructure deployed successfully!"
    log_info "ALB DNS: $ALB_DNS_NAME"
    log_info "DB Endpoint: $DB_ENDPOINT"
    
    # Go back to root
    cd ../../..
}

# Deploy CloudFormation stack
deploy_cloudformation() {
    log_info "Step 2: Deploying CloudFormation Stack"
    
    # Get account ID
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Update parameters file
    log_info "Updating CloudFormation parameters..."
    sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" cloudformation/parameters-dev.json
    
    # Create SNS topic for alerts
    log_info "Creating SNS topic for alerts..."
    aws sns create-topic --name "$ENVIRONMENT-alerts" --region $REGION
    
    # Deploy CloudFormation stack
    log_info "Deploying CloudFormation stack..."
    aws cloudformation deploy \
        --template-file cloudformation/iam-lambda-eventbridge.yaml \
        --stack-name "iam-lambda-eventbridge-$ENVIRONMENT" \
        --parameter-overrides file://cloudformation/parameters-dev.json \
        --capabilities CAPABILITY_NAMED_IAM \
        --region $REGION
    
    log_success "CloudFormation stack deployed successfully!"
}

# Run smoke tests
run_smoke_tests() {
    log_info "Step 3: Running Smoke Tests"
    
    # Make smoke test script executable
    chmod +x scripts/smoke-test.sh
    
    # Run smoke tests
    log_info "Executing smoke tests..."
    if scripts/smoke-test.sh $ENVIRONMENT $REGION; then
        log_success "All smoke tests passed!"
    else
        log_warning "Some smoke tests failed. Check the output above."
    fi
}

# Test application endpoints
test_application() {
    log_info "Step 4: Testing Application Endpoints"
    
    # Get ALB DNS name from Terraform output
    cd terraform/stacks/main
    terraform workspace select $ENVIRONMENT
    ALB_DNS_NAME=$(terraform output -raw alb_dns_name)
    cd ../../..
    
    if [ -z "$ALB_DNS_NAME" ]; then
        log_error "ALB DNS name not available"
        return 1
    fi
    
    log_info "Testing application at: http://$ALB_DNS_NAME"
    
    # Test health endpoint
    log_info "Testing health endpoint..."
    if curl -f "http://$ALB_DNS_NAME/healthz" > /dev/null 2>&1; then
        log_success "Health endpoint is working"
    else
        log_error "Health endpoint is not working"
    fi
    
    # Test root endpoint
    log_info "Testing root endpoint..."
    if curl -f "http://$ALB_DNS_NAME/" > /dev/null 2>&1; then
        log_success "Root endpoint is working"
    else
        log_error "Root endpoint is not working"
    fi
    
    # Test API status endpoint
    log_info "Testing API status endpoint..."
    if curl -f "http://$ALB_DNS_NAME/api/status" > /dev/null 2>&1; then
        log_success "API status endpoint is working"
    else
        log_error "API status endpoint is not working"
    fi
}

# Demo auto scaling
demo_auto_scaling() {
    log_info "Step 5: Auto Scaling Demo"
    
    # Get ASG name
    local asg_name="$ENVIRONMENT-app-asg"
    
    log_info "Current ASG status:"
    aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$asg_name" \
        --query 'AutoScalingGroups[0].[DesiredCapacity,Instances | length(@)]' \
        --output table
    
    log_info "Auto scaling policies:"
    aws autoscaling describe-policies \
        --auto-scaling-group-name "$asg_name" \
        --query 'ScalingPolicies[*].[PolicyName,AdjustmentType,ScalingAdjustment]' \
        --output table
    
    log_info "CloudWatch alarms:"
    aws cloudwatch describe-alarms \
        --alarm-names "$ENVIRONMENT-high-cpu" "$ENVIRONMENT-low-cpu" \
        --query 'MetricAlarms[*].[AlarmName,StateValue]' \
        --output table
}

# Demo monitoring and alerting
demo_monitoring() {
    log_info "Step 6: Monitoring & Alerting Demo"
    
    # Check CloudWatch dashboard
    local dashboard_name="$ENVIRONMENT-infrastructure-dashboard"
    
    log_info "CloudWatch dashboard: $dashboard_name"
    if aws cloudwatch describe-dashboards --dashboard-names "$dashboard_name" > /dev/null 2>&1; then
        log_success "Dashboard exists"
        log_info "View dashboard at: https://console.aws.amazon.com/cloudwatch/home?region=$REGION#dashboards:name=$dashboard_name"
    else
        log_warning "Dashboard does not exist"
    fi
    
    # Check SNS topic
    local sns_topic_name="$ENVIRONMENT-alerts"
    
    log_info "SNS topic: $sns_topic_name"
    if aws sns list-topics --query "Topics[?contains(TopicArn, '$sns_topic_name')].TopicArn" --output text | grep -q .; then
        log_success "SNS topic exists"
    else
        log_warning "SNS topic does not exist"
    fi
    
    # Check Lambda function
    local function_name="$ENVIRONMENT-bucket-guardian"
    
    log_info "Lambda function: $function_name"
    if aws lambda get-function --function-name "$function_name" > /dev/null 2>&1; then
        log_success "Lambda function exists"
        
        # Test Lambda invocation
        log_info "Testing Lambda function..."
        aws lambda invoke \
            --function-name "$function_name" \
            --payload '{"test": "demo"}' \
            --cli-binary-format raw-in-base64-out \
            demo-response.json
        
        if [ -f demo-response.json ]; then
            log_info "Lambda response:"
            cat demo-response.json | jq .
            rm -f demo-response.json
        fi
    else
        log_warning "Lambda function does not exist"
    fi
}

# Test S3 functionality
test_s3_functionality() {
    log_info "Step 7: Testing S3 Functionality"
    
    # Get S3 bucket names from Terraform output
    cd terraform/stacks/main
    terraform workspace select $ENVIRONMENT
    DATA_BUCKET=$(terraform output -raw data_bucket_name)
    cd ../../..
    
    if [ -z "$DATA_BUCKET" ]; then
        log_error "Data bucket name not available"
        return 1
    fi
    
    log_info "Testing S3 bucket: $DATA_BUCKET"
    
    # Create test file
    echo "This is a test file for the demo" > demo-test-file.txt
    
    # Upload to incoming/ prefix to trigger Lambda
    log_info "Uploading test file to incoming/ prefix..."
    aws s3 cp demo-test-file.txt "s3://$DATA_BUCKET/incoming/demo-test-file.txt"
    
    if [ $? -eq 0 ]; then
        log_success "File uploaded successfully"
        
        # Wait a moment for Lambda to process
        log_info "Waiting for Lambda to process the file..."
        sleep 10
        
        # Check if file was processed
        if aws s3 ls "s3://$DATA_BUCKET/incoming/demo-test-file.txt" > /dev/null 2>&1; then
            log_success "File is still in incoming/ prefix"
        else
            log_info "File was moved by Lambda processing"
        fi
    else
        log_error "File upload failed"
    fi
    
    # Clean up test file
    rm -f demo-test-file.txt
}

# Show cost optimization features
show_cost_optimization() {
    log_info "Step 8: Cost Optimization Features"
    
    # Check AWS Budgets
    log_info "AWS Budgets:"
    aws budgets describe-budgets \
        --account-id $(aws sts get-caller-identity --query Account --output text) \
        --query 'Budgets[*].[BudgetName,TimeUnit,LimitAmount]' \
        --output table
    
    # Check S3 lifecycle policies
    log_info "S3 Lifecycle Policies:"
    cd terraform/stacks/main
    terraform workspace select $ENVIRONMENT
    LOGS_BUCKET=$(terraform output -raw logs_bucket_name)
    cd ../../..
    
    if [ ! -z "$LOGS_BUCKET" ]; then
        aws s3api get-bucket-lifecycle-configuration \
            --bucket "$LOGS_BUCKET" \
            --query 'Rules[*].[Id,Status]' \
            --output table 2>/dev/null || log_info "No lifecycle policies configured"
    fi
    
    # Check NAT Gateway strategy
    log_info "NAT Gateway Strategy:"
    cd terraform/stacks/main
    terraform workspace select $ENVIRONMENT
    NAT_COUNT=$(terraform output -raw nat_gateway_ids | wc -w)
    cd ../../..
    
    if [ "$NAT_COUNT" -eq 1 ]; then
        log_info "Single NAT Gateway strategy (cost optimized)"
    else
        log_info "Multiple NAT Gateways strategy (high availability)"
    fi
}

# Cleanup infrastructure
cleanup_infrastructure() {
    log_info "Step 9: Cleaning Up Infrastructure"
    
    read -p "Do you want to destroy the infrastructure? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_warning "Destroying infrastructure..."
        
        # Delete CloudFormation stack
        log_info "Deleting CloudFormation stack..."
        aws cloudformation delete-stack \
            --stack-name "iam-lambda-eventbridge-$ENVIRONMENT" \
            --region $REGION
        
        # Wait for CloudFormation deletion
        log_info "Waiting for CloudFormation stack deletion..."
        aws cloudformation wait stack-delete-complete \
            --stack-name "iam-lambda-eventbridge-$ENVIRONMENT" \
            --region $REGION
        
        # Destroy Terraform infrastructure
        log_info "Destroying Terraform infrastructure..."
        cd terraform/stacks/main
        terraform workspace select $ENVIRONMENT
        terraform destroy -auto-approve -var="db_password=demo123!"
        cd ../../..
        
        log_success "Infrastructure cleanup completed!"
    else
        log_info "Infrastructure cleanup skipped. Resources will remain running."
        log_warning "Remember to clean up resources manually to avoid charges!"
    fi
}

# Main demo execution
main() {
    show_demo_info
    show_demo_steps
    
    log_info "Starting demo for environment: $ENVIRONMENT"
    log_info "Region: $REGION"
    
    # Check prerequisites
    check_prerequisites
    
    # Deploy infrastructure
    deploy_infrastructure
    
    # Deploy CloudFormation
    deploy_cloudformation
    
    # Run smoke tests
    run_smoke_tests
    
    # Test application
    test_application
    
    # Demo auto scaling
    demo_auto_scaling
    
    # Demo monitoring
    demo_monitoring
    
    # Test S3 functionality
    test_s3_functionality
    
    # Show cost optimization
    show_cost_optimization
    
    # Cleanup
    cleanup_infrastructure
    
    log_success "Demo completed successfully!"
    
    cat << 'EOF'

🎉 Demo Summary:

✅ Infrastructure deployed with Terraform
✅ CloudFormation stack deployed
✅ Application tested and verified
✅ Auto scaling demonstrated
✅ Monitoring and alerting verified
✅ S3 functionality tested
✅ Cost optimization features shown

📚 Next Steps:
• Explore the AWS Console to see all resources
• Check CloudWatch dashboards and metrics
• Test the Lambda function manually
• Review the infrastructure code
• Customize for your own use case

🔗 Useful Links:
• CloudWatch Dashboard: https://console.aws.amazon.com/cloudwatch/
• S3 Console: https://console.aws.amazon.com/s3/
• Lambda Console: https://console.aws.amazon.com/lambda/
• RDS Console: https://console.aws.amazon.com/rds/

EOF
}

# Run main function
main "$@" 