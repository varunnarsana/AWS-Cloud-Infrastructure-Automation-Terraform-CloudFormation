#!/usr/bin/env python3
"""
AWS Cloud Infrastructure Automation Demo Application
A simple Flask API that demonstrates the infrastructure deployment
"""

import os
import logging
import psycopg2
from datetime import datetime
from flask import Flask, jsonify, request
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize Flask app
app = Flask(__name__)

# Database connection function
def get_db_connection():
    """Create and return a database connection"""
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
    """Test database connectivity and return status"""
    try:
        conn = get_db_connection()
        if conn:
            # Test with a simple query
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
    """Health check endpoint for load balancer"""
    try:
        # Check database connectivity
        db_healthy, db_info = test_db_connection()
        
        # Basic system health
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
    """Root endpoint with application information"""
    return jsonify({
        'message': 'AWS Cloud Infrastructure Automation Demo',
        'description': 'A production-grade AWS infrastructure using Terraform and CloudFormation',
        'timestamp': datetime.utcnow().isoformat(),
        'environment': os.getenv('ENVIRONMENT', 'unknown'),
        'version': '1.0.0',
        'endpoints': {
            'health': '/healthz',
            'status': '/api/status',
            'info': '/api/info'
        }
    })

@app.route('/api/status')
def api_status():
    """API status endpoint"""
    try:
        db_healthy, _ = test_db_connection()
        
        return jsonify({
            'status': 'operational' if db_healthy else 'degraded',
            'timestamp': datetime.utcnow().isoformat(),
            'environment': os.getenv('ENVIRONMENT', 'unknown'),
            'database': 'connected' if db_healthy else 'disconnected',
            'uptime': 'running'
        })
        
    except Exception as e:
        logger.error(f"Status check failed: {e}")
        return jsonify({
            'status': 'error',
            'timestamp': datetime.utcnow().isoformat(),
            'error': str(e)
        }), 500

@app.route('/api/info')
def api_info():
    """Application information endpoint"""
    return jsonify({
        'application': 'AWS Cloud Infrastructure Demo',
        'framework': 'Flask',
        'python_version': os.sys.version,
        'environment': os.getenv('ENVIRONMENT', 'unknown'),
        'database_host': os.getenv('DB_HOST', 'not_set'),
        'database_name': os.getenv('DB_NAME', 'not_set'),
        'timestamp': datetime.utcnow().isoformat()
    })

@app.route('/api/db/test')
def db_test():
    """Database test endpoint"""
    try:
        conn = get_db_connection()
        if conn:
            with conn.cursor() as cur:
                # Test basic operations
                cur.execute('SELECT current_timestamp, version();')
                result = cur.fetchone()
                conn.close()
                
                return jsonify({
                    'status': 'success',
                    'database': 'connected',
                    'timestamp': result[0].isoformat() if result[0] else None,
                    'version': result[1] if result[1] else 'Unknown',
                    'message': 'Database connection and query successful'
                })
        else:
            return jsonify({
                'status': 'error',
                'database': 'disconnected',
                'message': 'Could not establish database connection'
            }), 500
            
    except Exception as e:
        logger.error(f"Database test failed: {e}")
        return jsonify({
            'status': 'error',
            'database': 'error',
            'message': str(e)
        }), 500

@app.route('/api/metrics')
def metrics():
    """Basic metrics endpoint"""
    try:
        # Get basic system metrics
        import psutil
        
        return jsonify({
            'timestamp': datetime.utcnow().isoformat(),
            'system': {
                'cpu_percent': psutil.cpu_percent(interval=1),
                'memory_percent': psutil.virtual_memory().percent,
                'disk_percent': psutil.disk_usage('/').percent
            },
            'environment': os.getenv('ENVIRONMENT', 'unknown')
        })
        
    except ImportError:
        return jsonify({
            'timestamp': datetime.utcnow().isoformat(),
            'message': 'psutil not available for system metrics',
            'environment': os.getenv('ENVIRONMENT', 'unknown')
        })
    except Exception as e:
        logger.error(f"Metrics collection failed: {e}")
        return jsonify({
            'timestamp': datetime.utcnow().isoformat(),
            'error': str(e)
        }), 500

@app.errorhandler(404)
def not_found(error):
    """Handle 404 errors"""
    return jsonify({
        'error': 'Not Found',
        'message': 'The requested resource was not found',
        'timestamp': datetime.utcnow().isoformat()
    }), 404

@app.errorhandler(500)
def internal_error(error):
    """Handle 500 errors"""
    logger.error(f"Internal server error: {error}")
    return jsonify({
        'error': 'Internal Server Error',
        'message': 'An internal server error occurred',
        'timestamp': datetime.utcnow().isoformat()
    }), 500

if __name__ == '__main__':
    # Get configuration from environment
    host = os.getenv('HOST', '0.0.0.0')
    port = int(os.getenv('PORT', '8080'))
    debug = os.getenv('DEBUG', 'false').lower() == 'true'
    
    logger.info(f"Starting application on {host}:{port}")
    logger.info(f"Environment: {os.getenv('ENVIRONMENT', 'unknown')}")
    logger.info(f"Database host: {os.getenv('DB_HOST', 'not_set')}")
    
    # Run the application
    app.run(
        host=host,
        port=port,
        debug=debug,
        threaded=True
    ) 