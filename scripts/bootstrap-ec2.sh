#!/bin/bash

# AWS Cloud Infrastructure Automation - EC2 Bootstrap Script
# This script is executed when EC2 instances start up

set -e

# Logging
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting EC2 instance bootstrap..."

# Update system packages
yum update -y

# Install required packages
yum install -y docker git curl wget jq

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Install Python 3 and pip
yum install -y python3 python3-pip

# Create application directory
mkdir -p /opt/app
cd /opt/app

# Get instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)

echo "Instance ID: $INSTANCE_ID"
echo "Region: $REGION"
echo "Availability Zone: $AZ"

# Get environment from instance tags
ENVIRONMENT=$(aws ec2 describe-tags \
    --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=Environment" \
    --region $REGION \
    --query 'Tags[0].Value' \
    --output text)

if [ -z "$ENVIRONMENT" ] || [ "$ENVIRONMENT" = "None" ]; then
    ENVIRONMENT="dev"
fi

echo "Environment: $ENVIRONMENT"

# Get database credentials from SSM Parameter Store
DB_HOST=$(aws ssm get-parameter \
    --name "/$ENVIRONMENT/db_host" \
    --region $REGION \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "")

DB_NAME=$(aws ssm get-parameter \
    --name "/$ENVIRONMENT/db_name" \
    --region $REGION \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "appdb")

DB_USER=$(aws ssm get-parameter \
    --name "/$ENVIRONMENT/db_user" \
    --region $REGION \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "dbadmin")

DB_PASSWORD=$(aws ssm get-parameter \
    --name "/$ENVIRONMENT/db_password" \
    --region $REGION \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "")

# If SSM parameters are not available, use environment variables or defaults
if [ -z "$DB_HOST" ]; then
    echo "Warning: DB_HOST not found in SSM, using default"
    DB_HOST="localhost"
fi

if [ -z "$DB_PASSWORD" ]; then
    echo "Warning: DB_PASSWORD not found in SSM, using default"
    DB_PASSWORD="changeme"
fi

echo "Database configuration:"
echo "  Host: $DB_HOST"
echo "  Name: $DB_NAME"
echo "  User: $DB_USER"

# Create environment file
cat > .env << EOF
DB_HOST=$DB_HOST
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_PORT=5432
ENVIRONMENT=$ENVIRONMENT
HOST=0.0.0.0
PORT=8080
DEBUG=false
EOF

# Create application configuration
cat > app.py << 'EOF'
from flask import Flask, jsonify, request
import os
import psycopg2
from datetime import datetime
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Database connection function
def get_db_connection():
    try:
        conn = psycopg2.connect(
            host=os.getenv('DB_HOST'),
            database=os.getenv('DB_NAME'),
            user=os.getenv('DB_USER'),
            password=os.getenv('DB_PASSWORD'),
            port=os.getenv('DB_PORT', '5432')
        )
        return conn
    except Exception as e:
        logger.error(f"Database connection failed: {e}")
        return None

def test_db_connection():
    try:
        conn = get_db_connection()
        if conn:
            with conn.cursor() as cur:
                cur.execute('SELECT version();')
                version = cur.fetchone()
            conn.close()
            return True, version[0] if version else "Unknown"
        return False, "No connection"
    except Exception as e:
        logger.error(f"Database test failed: {e}")
        return False, str(e)

@app.route('/healthz')
def health_check():
    try:
        db_healthy, db_info = test_db_connection()
        
        health_status = {
            'status': 'healthy' if db_healthy else 'unhealthy',
            'timestamp': datetime.utcnow().isoformat(),
            'environment': os.getenv('ENVIRONMENT', 'unknown'),
            'database': {
                'connected': db_healthy,
                'info': db_info
            },
            'version': '1.0.0'
        }
        
        status_code = 200 if db_healthy else 503
        return jsonify(health_status), status_code
        
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return jsonify({
            'status': 'unhealthy',
            'timestamp': datetime.utcnow().isoformat(),
            'error': str(e)
        }), 503

@app.route('/')
def root():
    return jsonify({
        'message': 'AWS Cloud Infrastructure Automation Demo',
        'timestamp': datetime.utcnow().isoformat(),
        'environment': os.getenv('ENVIRONMENT', 'unknown'),
        'version': '1.0.0'
    })

@app.route('/api/status')
def api_status():
    try:
        db_healthy, _ = test_db_connection()
        
        return jsonify({
            'status': 'operational' if db_healthy else 'degraded',
            'timestamp': datetime.utcnow().isoformat(),
            'environment': os.getenv('ENVIRONMENT', 'unknown'),
            'database': 'connected' if db_healthy else 'disconnected'
        })
        
    except Exception as e:
        logger.error(f"Status check failed: {e}")
        return jsonify({
            'status': 'error',
            'timestamp': datetime.utcnow().isoformat(),
            'error': str(e)
        }), 500

if __name__ == '__main__':
    host = os.getenv('HOST', '0.0.0.0')
    port = int(os.getenv('PORT', '8080'))
    debug = os.getenv('DEBUG', 'false').lower() == 'true'
    
    logger.info(f"Starting application on {host}:{port}")
    logger.info(f"Environment: {os.getenv('ENVIRONMENT', 'unknown')}")
    
    app.run(host=host, port=port, debug=debug, threaded=True)
EOF

# Create requirements.txt
cat > requirements.txt << 'EOF'
Flask==2.3.3
psycopg2-binary==2.9.7
Werkzeug==2.3.7
python-dotenv==1.0.0
EOF

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8080

CMD ["python", "app.py"]
EOF

# Build Docker image
echo "Building Docker image..."
docker build -t app:latest .

# Create systemd service for the application
cat > /etc/systemd/system/app.service << 'EOF'
[Unit]
Description=Flask Application
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker run --rm -d --name app -p 8080:8080 --env-file /opt/app/.env app:latest
ExecStop=/usr/bin/docker stop app
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl enable app.service
systemctl start app.service

# Create health check script
cat > /opt/app/health_check.sh << 'EOF'
#!/bin/bash
curl -f http://localhost:8080/healthz > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Application is healthy"
    exit 0
else
    echo "Application is unhealthy"
    exit 1
fi
EOF

chmod +x /opt/app/health_check.sh

# Set up CloudWatch agent for monitoring
yum install -y amazon-cloudwatch-agent

# Create CloudWatch agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "root"
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/messages",
                        "log_group_name": "/aws/ec2/app",
                        "log_stream_name": "$INSTANCE_ID"
                    },
                    {
                        "file_path": "/var/log/user-data.log",
                        "log_group_name": "/aws/ec2/app",
                        "log_stream_name": "$INSTANCE_ID/user-data"
                    }
                ]
            }
        }
    },
    "metrics": {
        "metrics_collected": {
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
            }
        }
    }
}
EOF

# Start CloudWatch agent
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Wait for application to be ready
echo "Waiting for application to be ready..."
sleep 30

# Test the application
if curl -f http://localhost:8080/healthz > /dev/null 2>&1; then
    echo "Application is running successfully"
else
    echo "Application failed to start"
    exit 1
fi

# Output instance information
echo "Instance bootstrap completed at $(date)"
echo "Environment: $ENVIRONMENT"
echo "Database endpoint: $DB_HOST"
echo "Application will be available on port 8080"

# Test external connectivity
echo "Testing external connectivity..."
if curl -f http://$DB_HOST:5432 > /dev/null 2>&1; then
    echo "Database connectivity test passed"
else
    echo "Database connectivity test failed (this is expected if DB is not accessible from this instance)"
fi

echo "Bootstrap script completed successfully" 