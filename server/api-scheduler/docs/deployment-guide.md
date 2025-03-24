# Stable Diffusion Asynchronous Inference Service - EC2 AutoScalingGroup Deployment Guide

[![en](https://img.shields.io/badge/lang-English-blue.svg)](deployment-guide.md)
[![zh-cn](https://img.shields.io/badge/语言-中文-red.svg)](deployment-guide.zh-CN.md)

## Architecture Overview

This solution implements an elastically scalable Stable Diffusion asynchronous inference cluster using AWS CDK, with the following key components:

1. **EC2 AutoScalingGroup**: A cluster of instances running the api-scheduler service
2. **Containerized Deployment**: Running the api-scheduler service in Docker containers
3. **Gradual Deployment Mechanism**: Supporting percentage-based instance updates
4. **Rollback Mechanism**: One-click rollback to the previous stable version

## EC2 AutoScalingGroup Deployment Logic

### 1. Infrastructure Components

- **VPC and Security Groups**: Providing network isolation and secure access control for EC2 instances
- **IAM Roles**: Granting EC2 instances permissions to access AWS services
- **Launch Templates**: Defining EC2 instance configurations, including instance type, AMI, user data scripts, etc.
- **Auto Scaling Group**: Automatically adjusting instance count based on SQS queue depth

### 2. Instance Configuration

- Using GPU instances (g4dn.xlarge) for efficient inference
- Automatically configuring instances via user data scripts:
  - Installing necessary software packages
  - Configuring CloudWatch agent
  - Pulling specified Docker image versions from ECR
  - Configuring and starting the api-scheduler service

### 3. Auto Scaling Policies

- Scaling based on SQS queue depth:
  - Queue messages < 10: Maintain current capacity
  - Queue messages 10-50: Add 1 instance
  - Queue messages 50-100: Add 2 instances
  - Queue messages > 100: Add 3 instances
- Automatically reducing instance count when queue is empty

## Image Updates and Gradual Deployment Mechanism

### 1. Image Building and Pushing

- Building api-scheduler images using Docker
- Pushing images to Amazon ECR
- Supporting versioned management with unique identifiers for each version

### 2. Version Tracking

- Using SSM Parameter Store to store current image version
- Storing previous stable version for rollback purposes
- Recording deployment status (stable, in-progress, rolling-back)

### 3. Gradual Deployment Process

- **Build Image**: Build and push new version image to ECR
- **Gradual Deployment**: Update instances by specified percentage
  - Update image version in SSM parameters
  - Trigger Instance Refresh in AutoScalingGroup
  - Monitor deployment progress and health status
- **Automatic Rollback**: Automatically roll back to previous stable version if deployment fails
- **Manual Rollback**: Providing scripts to support manual rollback operations

## Health Checks and Monitoring

- **Application Health Checks**: Periodically checking if the API service responds normally
- **CloudWatch Monitoring**: Collecting key metrics from instances and applications
- **Log Management**: Sending application logs and health check logs to CloudWatch Logs
- **Deployment Status Tracking**: Recording and querying deployment status via SSM parameters

## Usage Instructions

### Deploy Infrastructure

```bash
cd cdk
npm install
./deploy.sh
```

### Build and Push New Image

```bash
cd cdk/scripts
./build-and-push-image.sh <deployment-id> <version>
```

### Gradual Deployment of New Version

```bash
cd cdk/scripts
./deploy-new-version.sh <deployment-id> <version> --percentage 20
```

### Rollback to Previous Stable Version

```bash
cd cdk/scripts
./rollback.sh <deployment-id>
```

## Best Practices

1. **High Availability**: Gradual deployment ensures service continuity
2. **Cost Optimization**: Auto-scaling based on queue depth
3. **Observability**: Comprehensive monitoring and logging
4. **Security**: Least privilege IAM policies and network isolation
5. **Gradual Deployment**: Controlling deployment risks with quick rollback capability
6. **Containerized Deployment**: Standardized runtime environment, simplified deployment process
