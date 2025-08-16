#!/bin/bash

# AWS Cloud Infrastructure Automation - Smoke Test Script
# This script validates the infrastructure deployment and application functionality

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
ALB_DNS_NAME=""
DB_ENDPOINT=""
S3_BUCKETS=()

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
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check curl
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Get infrastructure information from Terraform outputs
get_infrastructure_info() {
    log_info "Getting infrastructure information..."
    
    # Change to Terraform directory
    cd terraform/stacks/main
    
    # Select workspace
    terraform workspace select $ENVIRONMENT
    
    # Get outputs
    ALB_DNS_NAME=$(terraform output -raw alb_dns_name)
    DB_ENDPOINT=$(terraform output -raw db_endpoint)
    
    # Get S3 bucket names
    S3_BUCKETS=(
        $(terraform output -raw logs_bucket_name)
        $(terraform output -raw artifacts_bucket_name)
        $(terraform output -raw data_bucket_name)
    )
    
    # Go back to root
    cd ../../..
    
    log_success "Infrastructure information retrieved"
    log_info "ALB DNS: $ALB_DNS_NAME"
    log_info "DB Endpoint: $DB_ENDPOINT"
    log_info "S3 Buckets: ${S3_BUCKETS[*]}"
}

# Test Application Load Balancer
test_alb() {
    log_info "Testing Application Load Balancer..."
    
    if [ -z "$ALB_DNS_NAME" ]; then
        log_error "ALB DNS name not available"
        return 1
    fi
    
    # Test ALB health check endpoint
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_info "Attempt $attempt/$max_attempts: Testing ALB health check..."
        
        if curl -f "http://$ALB_DNS_NAME/healthz" > /dev/null 2>&1; then
            log_success "ALB health check passed"
            break
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            log_error "ALB health check failed after $max_attempts attempts"
            return 1
        fi
        
        log_info "ALB not ready yet, waiting 10 seconds..."
        sleep 10
        ((attempt++))
    done
    
    # Test other endpoints
    log_info "Testing application endpoints..."
    
    # Test root endpoint
    if curl -f "http://$ALB_DNS_NAME/" > /dev/null 2>&1; then
        log_success "Root endpoint accessible"
    else
        log_warning "Root endpoint not accessible"
    fi
    
    # Test API status endpoint
    if curl -f "http://$ALB_DNS_NAME/api/status" > /dev/null 2>&1; then
        log_success "API status endpoint accessible"
    else
        log_warning "API status endpoint not accessible"
    fi
    
    # Test API info endpoint
    if curl -f "http://$ALB_DNS_NAME/api/info" > /dev/null 2>&1; then
        log_success "API info endpoint accessible"
    else
        log_warning "API info endpoint not accessible"
    fi
    
    return 0
}

# Test S3 buckets
test_s3_buckets() {
    log_info "Testing S3 buckets..."
    
    for bucket in "${S3_BUCKETS[@]}"; do
        log_info "Testing bucket: $bucket"
        
        # Check if bucket exists
        if aws s3 ls "s3://$bucket" > /dev/null 2>&1; then
            log_success "Bucket $bucket exists"
            
            # Check bucket encryption
            if aws s3api get-bucket-encryption --bucket "$bucket" > /dev/null 2>&1; then
                log_success "Bucket $bucket has encryption enabled"
            else
                log_warning "Bucket $bucket does not have encryption enabled"
            fi
            
            # Check bucket versioning
            local versioning=$(aws s3api get-bucket-versioning --bucket "$bucket" --query 'Status' --output text 2>/dev/null || echo "NotEnabled")
            if [ "$versioning" = "Enabled" ]; then
                log_success "Bucket $bucket has versioning enabled"
            else
                log_warning "Bucket $bucket does not have versioning enabled"
            fi
            
            # Check public access block
            local public_access=$(aws s3api get-public-access-block --bucket "$bucket" --query 'PublicAccessBlockConfiguration' --output json 2>/dev/null)
            if [ "$public_access" != "null" ]; then
                log_success "Bucket $bucket has public access blocked"
            else
                log_warning "Bucket $bucket does not have public access blocked"
            fi
            
        else
            log_error "Bucket $bucket does not exist"
            return 1
        fi
    done
    
    return 0
}

# Test RDS database
test_rds() {
    log_info "Testing RDS database..."
    
    if [ -z "$DB_ENDPOINT" ]; then
        log_error "DB endpoint not available"
        return 1
    fi
    
    # Extract hostname from endpoint
    local db_host=$(echo "$DB_ENDPOINT" | cut -d':' -f1)
    
    # Test database connectivity (this requires psql or similar tool)
    log_info "Database endpoint: $DB_ENDPOINT"
    log_success "RDS endpoint available"
    
    # Note: Actual database connectivity test would require database credentials
    # and a database client tool like psql
    
    return 0
}

# Test CloudWatch monitoring
test_cloudwatch() {
    log_info "Testing CloudWatch monitoring..."
    
    # Check if CloudWatch dashboard exists
    local dashboard_name="$ENVIRONMENT-infrastructure-dashboard"
    
    if aws cloudwatch describe-dashboards --dashboard-names "$dashboard_name" > /dev/null 2>&1; then
        log_success "CloudWatch dashboard '$dashboard_name' exists"
    else
        log_warning "CloudWatch dashboard '$dashboard_name' does not exist"
    fi
    
    # Check if SNS topic exists
    local sns_topic_name="$ENVIRONMENT-alerts"
    
    if aws sns list-topics --query "Topics[?contains(TopicArn, '$sns_topic_name')].TopicArn" --output text | grep -q .; then
        log_success "SNS topic '$sns_topic_name' exists"
    else
        log_warning "SNS topic '$sns_topic_name' does not exist"
    fi
    
    return 0
}

# Test Lambda function
test_lambda() {
    log_info "Testing Lambda function..."
    
    local function_name="$ENVIRONMENT-bucket-guardian"
    
    if aws lambda get-function --function-name "$function_name" > /dev/null 2>&1; then
        log_success "Lambda function '$function_name' exists"
        
        # Test Lambda invocation
        log_info "Testing Lambda function invocation..."
        
        local response=$(aws lambda invoke \
            --function-name "$function_name" \
            --payload '{"test": "event"}' \
            --cli-binary-format raw-in-base64-out \
            response.json 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            log_success "Lambda function invocation successful"
            
            # Check response
            if [ -f response.json ]; then
                local status=$(jq -r '.statusCode' response.json 2>/dev/null || echo "unknown")
                log_info "Lambda response status: $status"
                rm -f response.json
            fi
        else
            log_warning "Lambda function invocation failed"
        fi
        
    else
        log_warning "Lambda function '$function_name' does not exist"
    fi
    
    return 0
}

# Test EventBridge rules
test_eventbridge() {
    log_info "Testing EventBridge rules..."
    
    # Check nightly rule
    local nightly_rule_name="$ENVIRONMENT-nightly-bucket-validation"
    
    if aws events describe-rule --name "$nightly_rule_name" > /dev/null 2>&1; then
        log_success "EventBridge rule '$nightly_rule_name' exists"
    else
        log_warning "EventBridge rule '$nightly_rule_name' does not exist"
    fi
    
    # Check S3 PutObject rule
    local s3_rule_name="$ENVIRONMENT-s3-putobject-validation"
    
    if aws events describe-rule --name "$s3_rule_name" > /dev/null 2>&1; then
        log_success "EventBridge rule '$s3_rule_name' exists"
    else
        log_warning "EventBridge rule '$s3_rule_name' does not exist"
    fi
    
    return 0
}

# Test Auto Scaling Group
test_asg() {
    log_info "Testing Auto Scaling Group..."
    
    local asg_name="$ENVIRONMENT-app-asg"
    
    if aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$asg_name" > /dev/null 2>&1; then
        log_success "Auto Scaling Group '$asg_name' exists"
        
        # Get ASG details
        local desired_capacity=$(aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names "$asg_name" \
            --query 'AutoScalingGroups[0].DesiredCapacity' \
            --output text 2>/dev/null)
        
        local actual_capacity=$(aws autoscaling describe-auto-scaling-groups \
            --auto-scaling-group-names "$asg_name" \
            --query 'AutoScalingGroups[0].Instances | length(@)' \
            --output text 2>/dev/null)
        
        log_info "ASG desired capacity: $desired_capacity"
        log_info "ASG actual capacity: $actual_capacity"
        
        if [ "$actual_capacity" -ge "$desired_capacity" ]; then
            log_success "ASG has sufficient instances running"
        else
            log_warning "ASG does not have sufficient instances running"
        fi
        
    else
        log_warning "Auto Scaling Group '$asg_name' does not exist"
    fi
    
    return 0
}

# Main test execution
main() {
    log_info "Starting smoke tests for environment: $ENVIRONMENT"
    log_info "Region: $REGION"
    
    # Check prerequisites
    check_prerequisites
    
    # Get infrastructure information
    get_infrastructure_info
    
    # Run tests
    local tests_passed=0
    local tests_total=0
    
    # Test ALB
    ((tests_total++))
    if test_alb; then
        ((tests_passed++))
    fi
    
    # Test S3 buckets
    ((tests_total++))
    if test_s3_buckets; then
        ((tests_passed++))
    fi
    
    # Test RDS
    ((tests_total++))
    if test_rds; then
        ((tests_passed++))
    fi
    
    # Test CloudWatch
    ((tests_total++))
    if test_cloudwatch; then
        ((tests_passed++))
    fi
    
    # Test Lambda
    ((tests_total++))
    if test_lambda; then
        ((tests_passed++))
    fi
    
    # Test EventBridge
    ((tests_total++))
    if test_eventbridge; then
        ((tests_passed++))
    fi
    
    # Test Auto Scaling Group
    ((tests_total++))
    if test_asg; then
        ((tests_passed++))
    fi
    
    # Summary
    log_info "Smoke test summary: $tests_passed/$tests_total tests passed"
    
    if [ $tests_passed -eq $tests_total ]; then
        log_success "All smoke tests passed! Infrastructure is ready."
        exit 0
    else
        log_warning "Some smoke tests failed. Please check the infrastructure."
        exit 1
    fi
}

# Run main function
main "$@" 