import signal
import sys
import logging
from scheduler import sqs
from scheduler.health_check import init_health_check
from scheduler.api_server import init_api_server
from scheduler.conf import schedulerConfig

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('main')

# Global variables for graceful shutdown
health_checker = None
api_server = None

def signal_handler(sig, frame):
    """Handle termination signals for graceful shutdown"""
    logger.info("Received termination signal, shutting down...")
    
    # Stop health checker
    if health_checker:
        health_checker.stop()
        
    # Stop API server
    if api_server:
        api_server.stop()
        
    sys.exit(0)

if __name__ == "__main__":
    # Register signal handlers for graceful shutdown
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        # Initialize and start health check service
        health_checker = init_health_check()
        health_checker.start()
        
        # Initialize and start API server for health checks
        api_port = int(schedulerConfig.get('api', 'port', fallback='8080'))
        api_server = init_api_server(api_port)
        api_server.start()
        
        # Start processing SQS messages
        logger.info("Starting SQS message processing...")
        sqs.receiveAndProcess()
    except Exception as e:
        logger.error(f"Error in main process: {e}")
        sys.exit(1)