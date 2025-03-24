import boto3
import os
import time
import threading
import logging
from datetime import datetime
import socket
import requests
from scheduler.conf import schedulerConfig

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('health_check')

class HealthCheck:
    def __init__(self):
        self.region = schedulerConfig.get('aws', 'region')
        # Get instance metadata
        self.instance_id = self._get_instance_metadata('instance-id')
        # Get deployment ID from instance tags
        self.deployment_id = self._get_deployment_id()
        self.autoscaling_client = boto3.client('autoscaling', region_name=self.region)
        self.ec2_client = boto3.client('ec2', region_name=self.region)
        self.health_check_interval = 60  # seconds
        self.health_check_thread = None
        self.running = False
        self.last_health_check_time = None
        self.health_status = "HEALTHY"
        
        logger.info(f"Health check initialized for instance {self.instance_id} in deployment {self.deployment_id}")

    def _get_instance_metadata(self, metadata_path):
        """Get EC2 instance metadata"""
        try:
            # First get a token
            token_url = "http://169.254.169.254/latest/api/token"
            token_headers = {"X-aws-ec2-metadata-token-ttl-seconds": "21600"}
            token_response = requests.put(token_url, headers=token_headers, timeout=2)
            token = token_response.text
            
            # Then use the token to get metadata
            url = f"http://169.254.169.254/latest/meta-data/{metadata_path}"
            headers = {"X-aws-ec2-metadata-token": token}
            response = requests.get(url, headers=headers, timeout=2)
            return response.text
        except Exception as e:
            logger.error(f"Error getting instance metadata: {e}")
            return None

    def _get_deployment_id(self):
        """Get deployment ID from instance tags"""
        try:
            response = self.ec2_client.describe_tags(
                Filters=[
                    {
                        'Name': 'resource-id',
                        'Values': [self.instance_id]
                    },
                    {
                        'Name': 'key',
                        'Values': ['DeploymentId']
                    }
                ]
            )
            if response['Tags']:
                return response['Tags'][0]['Value']
            return None
        except Exception as e:
            logger.error(f"Error getting deployment ID: {e}")
            return None

    def _check_api_health(self):
        """Check if the API is responding correctly"""
        try:
            # Check local API health endpoint
            response = requests.get("http://localhost:8080/health", timeout=5)
            return response.status_code == 200
        except Exception as e:
            logger.error(f"API health check failed: {e}")
            return False

    def _check_gpu_health(self):
        """Check if GPU is available and functioning"""
        try:
            # This is a simplified check - in a real implementation, 
            # you might want to check GPU utilization or run a test inference
            # For now, we'll just check if the NVIDIA driver is loaded
            with open('/proc/driver/nvidia/version', 'r') as f:
                return True
        except Exception as e:
            logger.error(f"GPU health check failed: {e}")
            return False

    def _check_disk_space(self):
        """Check if there's enough disk space"""
        try:
            # Check if disk usage is below 90%
            import shutil
            total, used, free = shutil.disk_usage("/")
            percent_used = (used / total) * 100
            return percent_used < 90
        except Exception as e:
            logger.error(f"Disk space check failed: {e}")
            return False

    def _check_memory_usage(self):
        """Check if there's enough memory available"""
        try:
            # Check if memory usage is below 90%
            with open('/proc/meminfo', 'r') as f:
                mem_info = f.readlines()
            
            mem_total = 0
            mem_available = 0
            
            for line in mem_info:
                if 'MemTotal' in line:
                    mem_total = int(line.split()[1])
                elif 'MemAvailable' in line:
                    mem_available = int(line.split()[1])
            
            if mem_total > 0:
                percent_used = ((mem_total - mem_available) / mem_total) * 100
                return percent_used < 90
            return False
        except Exception as e:
            logger.error(f"Memory usage check failed: {e}")
            return False

    def _update_instance_health(self, is_healthy):
        """Update instance health status in AutoScaling group"""
        try:
            if is_healthy:
                self.health_status = "HEALTHY"
                logger.info(f"Instance {self.instance_id} is healthy")
            else:
                self.health_status = "UNHEALTHY"
                logger.warning(f"Instance {self.instance_id} is unhealthy, reporting to AutoScaling")
                
                # Report unhealthy status to AutoScaling
                self.autoscaling_client.set_instance_health(
                    InstanceId=self.instance_id,
                    HealthStatus='Unhealthy',
                    ShouldRespectGracePeriod=True
                )
        except Exception as e:
            logger.error(f"Error updating instance health: {e}")

    def perform_health_check(self):
        """Perform a comprehensive health check"""
        try:
            # Perform various health checks
            api_healthy = self._check_api_health()
            
            # These checks might fail in some environments, so we make them optional
            try:
                gpu_healthy = self._check_gpu_health()
            except:
                gpu_healthy = True  # Skip if not applicable
                
            try:
                disk_healthy = self._check_disk_space()
            except:
                disk_healthy = True  # Skip if not applicable
                
            try:
                memory_healthy = self._check_memory_usage()
            except:
                memory_healthy = True  # Skip if not applicable
            
            # Instance is healthy only if all checks pass
            is_healthy = api_healthy and gpu_healthy and disk_healthy and memory_healthy
            
            # Update instance health status
            self._update_instance_health(is_healthy)
            
            # Update last health check time
            self.last_health_check_time = datetime.now()
            
            # Log health check results
            logger.info(f"Health check results: API: {api_healthy}, GPU: {gpu_healthy}, "
                       f"Disk: {disk_healthy}, Memory: {memory_healthy}")
            
            return is_healthy
        except Exception as e:
            logger.error(f"Error performing health check: {e}")
            return False

    def _health_check_loop(self):
        """Background thread for periodic health checks"""
        while self.running:
            try:
                self.perform_health_check()
            except Exception as e:
                logger.error(f"Error in health check loop: {e}")
            
            # Sleep for the specified interval
            time.sleep(self.health_check_interval)

    def start(self):
        """Start the health check background thread"""
        if not self.running:
            self.running = True
            self.health_check_thread = threading.Thread(target=self._health_check_loop)
            self.health_check_thread.daemon = True
            self.health_check_thread.start()
            logger.info("Health check service started")

    def stop(self):
        """Stop the health check background thread"""
        if self.running:
            self.running = False
            if self.health_check_thread:
                self.health_check_thread.join(timeout=5)
            logger.info("Health check service stopped")

    def get_status(self):
        """Get current health status"""
        return {
            "status": self.health_status,
            "instance_id": self.instance_id,
            "deployment_id": self.deployment_id,
            "last_check": self.last_health_check_time.isoformat() if self.last_health_check_time else None
        }


# Singleton instance
health_checker = None

def init_health_check():
    """Initialize the health check service"""
    global health_checker
    if health_checker is None:
        health_checker = HealthCheck()
    return health_checker

def get_health_checker():
    """Get the health check service instance"""
    global health_checker
    if health_checker is None:
        health_checker = init_health_check()
    return health_checker
