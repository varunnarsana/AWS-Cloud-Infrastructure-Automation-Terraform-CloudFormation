#!/bin/bash

# Update system packages
yum update -y

# Install Docker
yum install -y docker
systemctl start docker
systemctl enable docker

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Install Python 3 and pip
yum install -y python3 python3-pip

# Install additional tools
yum install -y jq

# Create application directory
mkdir -p /opt/app
cd /opt/app

# Create environment file
cat > .env << EOF
DB_HOST=${db_endpoint}
DB_NAME=${db_name}
DB_USER=${db_username}
DB_PASSWORD=${db_password}
ENVIRONMENT=${environment}
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
            port=5432
        )
        return conn
    except Exception as e:
        logger.error(f"Database connection failed: {e}")
        return None

@app.route('/healthz')
def health_check():
    """Health check endpoint"""
    try:
        # Check database connectivity
        conn = get_db_connection()
        if conn:
            conn.close()
            return jsonify({
                'status': 'healthy',
                'timestamp': datetime.utcnow().isoformat(),
                'environment': os.getenv('ENVIRONMENT', 'unknown'),
                'database': 'connected'
            }), 200
        else:
            return jsonify({
                'status': 'unhealthy',
                'timestamp': datetime.utcnow().isoformat(),
                'environment': os.getenv('ENVIRONMENT', 'unknown'),
                'database': 'disconnected'
            }), 503
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return jsonify({
            'status': 'unhealthy',
            'timestamp': datetime.utcnow().isoformat(),
            'environment': os.getenv('ENVIRONMENT', 'unknown'),
            'error': str(e)
        }), 503

@app.route('/')
def root():
    """Root endpoint"""
    return jsonify({
        'message': 'AWS Cloud Infrastructure Automation Demo',
        'timestamp': datetime.utcnow().isoformat(),
        'environment': os.getenv('ENVIRONMENT', 'unknown'),
        'version': '1.0.0'
    })

@app.route('/api/status')
def api_status():
    """API status endpoint"""
    return jsonify({
        'status': 'operational',
        'timestamp': datetime.utcnow().isoformat(),
        'environment': os.getenv('ENVIRONMENT', 'unknown')
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
EOF

# Create requirements.txt
cat > requirements.txt << 'EOF'
Flask==2.3.3
psycopg2-binary==2.9.7
Werkzeug==2.3.7
EOF

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8080

CMD ["python", "app.py"]
EOF

# Build Docker image
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

# Create a simple health check script
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

# Set up CloudWatch agent for custom metrics
yum install -y amazon-cloudwatch-agent

# Create CloudWatch agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
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
                        "log_stream_name": "{instance_id}"
                    },
                    {
                        "file_path": "/opt/app/app.log",
                        "log_group_name": "/aws/ec2/app",
                        "log_stream_name": "{instance_id}/application"
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

# Output instance information
echo "Instance bootstrap completed at $(date)"
echo "Environment: ${environment}"
echo "Database endpoint: ${db_endpoint}"
echo "Application will be available on port 8080"

# Wait for application to be ready
sleep 30

# Test the application
if curl -f http://localhost:8080/healthz > /dev/null 2>&1; then
    echo "Application is running successfully"
else
    echo "Application failed to start"
    exit 1
fi 