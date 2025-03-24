import threading
import logging
import json
from http.server import HTTPServer, BaseHTTPRequestHandler
from scheduler.health_check import get_health_checker

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('api_server')

class HealthCheckHandler(BaseHTTPRequestHandler):
    def _set_headers(self, status_code=200):
        self.send_response(status_code)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        
    def do_GET(self):
        if self.path == '/health':
            # Get health status from the health checker
            health_checker = get_health_checker()
            status = health_checker.get_status()
            
            # Return 200 if healthy, 503 if unhealthy
            if status["status"] == "HEALTHY":
                self._set_headers(200)
            else:
                self._set_headers(503)
                
            # Return health status as JSON
            self.wfile.write(json.dumps(status).encode())
        else:
            self._set_headers(404)
            self.wfile.write(json.dumps({"error": "Not found"}).encode())
    
    def log_message(self, format, *args):
        logger.info("%s - - [%s] %s" % (self.client_address[0], self.log_date_time_string(), format % args))

class ApiServer:
    def __init__(self, port=8080):
        self.port = port
        self.server = None
        self.server_thread = None
        self.running = False
        
    def start(self):
        """Start the API server in a background thread"""
        if not self.running:
            self.running = True
            self.server_thread = threading.Thread(target=self._run_server)
            self.server_thread.daemon = True
            self.server_thread.start()
            logger.info(f"API server started on port {self.port}")
            
    def _run_server(self):
        """Run the HTTP server"""
        try:
            self.server = HTTPServer(('0.0.0.0', self.port), HealthCheckHandler)
            logger.info(f"Server running on port {self.port}")
            self.server.serve_forever()
        except Exception as e:
            logger.error(f"Error running API server: {e}")
            self.running = False
            
    def stop(self):
        """Stop the API server"""
        if self.running and self.server:
            self.server.shutdown()
            self.running = False
            if self.server_thread:
                self.server_thread.join(timeout=5)
            logger.info("API server stopped")

# Singleton instance
api_server = None

def init_api_server(port=8080):
    """Initialize the API server"""
    global api_server
    if api_server is None:
        api_server = ApiServer(port)
    return api_server

def get_api_server():
    """Get the API server instance"""
    global api_server
    if api_server is None:
        api_server = init_api_server()
    return api_server
