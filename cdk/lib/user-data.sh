#!/bin/bash
set -e

# Update system packages
yum update -y
yum install -y amazon-cloudwatch-agent git docker python3 python3-pip jq

# Start and enable Docker service
systemctl start docker
systemctl enable docker

# Configure CloudWatch agent
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
            "file_path": "/var/log/api-scheduler/application.log",
            "log_group_name": "sd-inference-api-scheduler",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 7
          },
          {
            "file_path": "/var/log/api-scheduler/health-check.log",
            "log_group_name": "sd-inference-health-check",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 7
          }
        ]
      }
    }
  },
  "metrics": {
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"]
      },
      "disk": {
        "measurement": ["disk_used_percent"],
        "resources": ["/"]
      },
      "cpu": {
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_user",
          "cpu_usage_system"
        ],
        "totalcpu": true
      }
    },
    "append_dimensions": {
      "InstanceId": "${aws:InstanceId}",
      "ImageVersion": "${image_version}"
    }
  }
}
EOF

# Start CloudWatch agent
systemctl start amazon-cloudwatch-agent
systemctl enable amazon-cloudwatch-agent

# Create directories
mkdir -p /opt/sd-inference
mkdir -p /var/log/api-scheduler

# Get instance metadata
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)
INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

# Get deployment ID from instance tags
DEPLOYMENT_ID=$(aws ec2 describe-tags --region $REGION --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=DeploymentId" --query "Tags[0].Value" --output text)

# Get current image version from SSM Parameter Store
IMAGE_VERSION=$(aws ssm get-parameter --region $REGION --name "/sd-inference/$DEPLOYMENT_ID/image-version" --query "Parameter.Value" --output text)

# Get deployment status
DEPLOYMENT_STATUS=$(aws ssm get-parameter --region $REGION --name "/sd-inference/$DEPLOYMENT_ID/deployment-status" --query "Parameter.Value" --output text)

# Store current version
echo "$IMAGE_VERSION" > /opt/sd-inference/current-version.txt

# Pull the Docker image from ECR
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/sd-inference-$DEPLOYMENT_ID"

# Login to ECR
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REPO

# Pull the specific version
echo "Pulling image $ECR_REPO:$IMAGE_VERSION"
docker pull $ECR_REPO:$IMAGE_VERSION

# Create configuration directory
mkdir -p /opt/sd-inference/config

# Create configuration file
cat > /opt/sd-inference/config/conf.ini << EOF
[aws]
region = $REGION
queue_url = sd-task-queue-$DEPLOYMENT_ID
table_name = sd-tasks-$DEPLOYMENT_ID
bucket_name = sd-images-$DEPLOYMENT_ID-$(echo $ACCOUNT_ID | cut -c1-5)

[api]
port = 8080
workers = 4
EOF

# Create health check script
cat > /opt/sd-inference/health-check.sh << 'EOF'
#!/bin/bash

# Simple health check that verifies the API is responding
HEALTH_CHECK_URL="http://localhost:8080/health"
HEALTH_LOG="/var/log/api-scheduler/health-check.log"

echo "$(date): Running health check..." >> $HEALTH_LOG

# Try to connect to the health endpoint
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" $HEALTH_CHECK_URL)

if [ "$RESPONSE" == "200" ]; then
  echo "$(date): Health check passed (HTTP $RESPONSE)" >> $HEALTH_LOG
  exit 0
else
  echo "$(date): Health check failed (HTTP $RESPONSE)" >> $HEALTH_LOG
  exit 1
fi
EOF

chmod +x /opt/sd-inference/health-check.sh

# Create systemd service file
cat > /etc/systemd/system/api-scheduler.service << EOF
[Unit]
Description=Stable Diffusion API Scheduler
After=network.target docker.service
Requires=docker.service

[Service]
User=root
WorkingDirectory=/opt/sd-inference
ExecStartPre=-/usr/bin/docker stop sd-api-scheduler
ExecStartPre=-/usr/bin/docker rm sd-api-scheduler
ExecStart=/usr/bin/docker run --name sd-api-scheduler \\
  --restart=unless-stopped \\
  -p 8080:8080 \\
  -v /opt/sd-inference/config:/app/config \\
  -e AWS_REGION=$REGION \\
  -e DEPLOYMENT_ID=$DEPLOYMENT_ID \\
  -e IMAGE_VERSION=$IMAGE_VERSION \\
  --log-driver=awslogs \\
  --log-opt awslogs-region=$REGION \\
  --log-opt awslogs-group=sd-inference-api-scheduler \\
  --log-opt awslogs-stream=$INSTANCE_ID \\
  $ECR_REPO:$IMAGE_VERSION
ExecStop=/usr/bin/docker stop sd-api-scheduler
Restart=always
RestartSec=10
StandardOutput=append:/var/log/api-scheduler/application.log
StandardError=append:/var/log/api-scheduler/application.log
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl daemon-reload
systemctl enable api-scheduler
systemctl start api-scheduler

# Wait for service to start
sleep 30

# Run initial health check
/opt/sd-inference/health-check.sh
HEALTH_CHECK_RESULT=$?

# Signal instance readiness based on health check
if [ $HEALTH_CHECK_RESULT -eq 0 ]; then
  # Signal success to CloudFormation
  /opt/aws/bin/cfn-signal --success true \
    --region $REGION \
    --stack $DEPLOYMENT_ID \
    --resource SdInferenceASG
  
  echo "Instance setup completed successfully"
else
  echo "Instance setup failed - health check did not pass"
  /opt/aws/bin/cfn-signal --success false \
    --region $REGION \
    --stack $DEPLOYMENT_ID \
    --resource SdInferenceASG
  exit 1
fi

# Setup cron job for health checks every minute
(crontab -l 2>/dev/null; echo "* * * * * /opt/sd-inference/health-check.sh") | crontab -
