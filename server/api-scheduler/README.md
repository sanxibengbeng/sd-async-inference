# API Scheduler for Stable Diffusion Inference Service

[![en](https://img.shields.io/badge/lang-English-blue.svg)](README.md)
[![zh-cn](https://img.shields.io/badge/语言-中文-red.svg)](README.zh-CN.md)

This component is responsible for processing tasks from the SQS queue and sending them to the Stable Diffusion API for inference.

## Features

- Processes tasks from SQS queue
- Updates task status in DynamoDB
- Uploads generated images to S3
- Provides health check endpoint for EC2 Auto Scaling
- Reports instance health status to Auto Scaling service

## Configuration

Create a `conf.ini` file based on the provided `conf.ini.example`:

```ini
[aws]
region = us-east-1
queue_url = sd-task-queue-deploymentid
table_name = sd-tasks-deploymentid
bucket_name = sd-images-deploymentid-12345

[api]
port = 8080
workers = 4
```

## Health Check Implementation

The API scheduler includes a health check implementation that:

1. Exposes a `/health` endpoint on port 8080
2. Performs periodic health checks on:
   - API availability
   - GPU status (if applicable)
   - Disk space usage
   - Memory usage
3. Reports unhealthy status to AWS Auto Scaling when issues are detected
4. Logs health check results for monitoring

## Running the Service

```bash
python3 main.py
```

The service will:
1. Start the health check service in the background
2. Start the API server for health check endpoint
3. Begin processing messages from the SQS queue

## Deployment

This service is typically deployed as a Docker container on EC2 instances within an Auto Scaling Group.
The deployment is managed by the CDK stack in the `cdk` directory.

For detailed deployment instructions, please refer to:
- [EC2 Auto Scaling Group Deployment Guide](./docs/deployment-guide.md)
- [Dockerfile Documentation](./Dockerfile)

## Docker Container

The service can be containerized using the provided Dockerfile:

```bash
# Build the Docker image
docker build -t api-scheduler:latest .

# Run the container
docker run -p 8080:8080 \
  -v /path/to/config:/app/config \
  -e AWS_REGION=us-east-1 \
  api-scheduler:latest
```

## Related Documentation

- [Main Project Documentation](../../README.md)
- [CDK Deployment Guide](../../cdk/README.md)
- [Lambda Function Documentation](../lambda/task_handler/README.md)
