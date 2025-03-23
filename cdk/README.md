# Stable Diffusion Inference Service CDK Deployment

[![en](https://img.shields.io/badge/lang-English-blue.svg)](README.md)
[![zh-cn](https://img.shields.io/badge/语言-中文-red.svg)](README.zh-CN.md)

This project uses AWS CDK to deploy the infrastructure required for the Stable Diffusion inference service, including API Gateway, Lambda, DynamoDB, SQS, S3, and CloudFront.

## Features

- **Unique Resource Names**: Each deployment generates unique resource names, allowing multiple deployments in the same AWS account
- **One-Click Deployment**: Simple deployment scripts that automate all steps
- **Complete Infrastructure**: Contains all necessary AWS resource configurations
- **Deployment Management**: Provides deploy, update, list, and delete scripts for managing multiple deployments

## Prerequisites

- Node.js (>= 18.x)
- AWS CLI configured
- AWS CDK installed (`npm install -g aws-cdk`)
- TypeScript (`npm install -g typescript`)
- jq (optional, for listing deployments)

## Deployment Management Scripts

This project provides four management scripts for easy operation of different deployments:

### 1. Deploy New Instance (deploy.sh)

```bash
# Create a new deployment (auto-generate deployment ID)
./deploy.sh

# Create a deployment with a specified deployment ID
./deploy.sh my-custom-id
```

After deployment, the deployment ID is saved to the `last_deployment_id.txt` file.

### 2. Update Existing Deployment (update.sh)

```bash
# Update the last deployed instance
./update.sh

# Update an instance with a specific deployment ID
./update.sh deploy-123456
```

### 3. List All Deployments (list-deployments.sh)

```bash
./list-deployments.sh
```

This will display all deployment stack names, creation times, and last update times.

### 4. Delete Deployment (destroy.sh)

```bash
# Delete the last deployed instance
./destroy.sh

# Delete an instance with a specific deployment ID
./destroy.sh deploy-123456
```

## Manual Deployment Steps

If you want to manually control the deployment process:

1. Install dependencies

```bash
cd cdk
npm install
```

2. Compile TypeScript code

```bash
npm run build
```

3. Bootstrap CDK (if using CDK for the first time in this AWS account/region)

```bash
cdk bootstrap
```

4. Deploy the stack (you can specify a custom deployment ID)

```bash
cdk deploy --context deploymentId=my-custom-id
```

5. Confirm deployment

During deployment, CDK will request confirmation to create IAM roles and security-related resources. Enter 'y' to confirm.

## Resource Description

This CDK project creates the following resources, all resource names contain a unique deployment ID:

- **DynamoDB Table**: `sd-tasks-{deploymentId}` - Stores task information
- **SQS Queue**: `sd-task-queue-{deploymentId}` - For storing pending inference tasks
- **S3 Bucket**: `sd-images-{deploymentId}-{accountId}` - Stores generated images
- **CloudFront Distribution**: Provides fast access to images
- **Lambda Functions**:
  - `TaskHandlerFunction` - Handles task submission and status queries
- **API Gateway**: `sdapi-{deploymentId}` - Provides REST API interface
  - POST /task: Submit task
  - GET /task?taskId={id}: Query task status
- **IAM Role**: `sd-inference-ec2-role-{deploymentId}` - Provides necessary permissions for EC2 inference instances

## Multiple Deployments

Since all resource names contain unique identifiers, you can deploy this stack multiple times in the same AWS account. Each deployment will create a completely new set of resources that don't interfere with each other.

## Notes

- This deployment only includes the infrastructure part, not the EC2 Spot Fleet configuration and auto-scaling part
- Resource deletion policies and security settings should be adjusted for production environments
- Lambda function code needs to be obtained from the project's `server/lambda` directory
- All scripts automatically detect and use the default region configured in AWS CLI
- If you encounter a "You must specify a region" error, run `aws configure` to set the default region

## Environment Setup

### Node.js Version Requirements

AWS CDK requires Node.js v18 or v20. If you're using an older version of Node.js (like v16), you'll receive warnings and may encounter deployment issues.

### Quick Setup

We provide an automated script to set up the correct Node.js environment:

```bash
# Set up Node.js environment
./setup-node.sh

# Fix security vulnerabilities
./fix-vulnerabilities.sh
```

### Manual Setup

If you want to set up the environment manually, follow these steps:

1. Install nvm (Node Version Manager):
```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
```

2. Load nvm (may need to reopen terminal):
```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
```

3. Install Node.js v18:
```bash
nvm install 18
```

4. Use Node.js v18:
```bash
nvm use 18
```

5. Set as default version:
```bash
nvm alias default 18
```

### Automatic Version Check

All deployment scripts now include Node.js version check functionality. If an incompatible version is detected:
- If nvm is installed, the script will try to automatically switch to Node.js v18
- If nvm is not installed, the script will prompt you to install the appropriate version

## Security Considerations

There are some security vulnerabilities in the project dependencies, mainly from AWS CDK-related libraries and other dependencies. To fix these vulnerabilities, you can run the provided fix script:

```bash
cd cdk
./fix-vulnerabilities.sh
```

This script will:
1. Update AWS CDK-related dependencies to the latest versions
2. Update other dependencies with vulnerabilities
3. Run npm audit fix to attempt automatic fixes
4. If there are still high or critical vulnerabilities, attempt forced fixes

Please note that forced updates may cause compatibility issues. After updating, ensure the project still works properly.
