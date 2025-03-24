#!/bin/bash
set -e

# This script builds and pushes a new Docker image for the api-scheduler
# Usage: ./build-and-push-image.sh <deployment-id> <version>

if [ $# -lt 2 ]; then
  echo "Usage: $0 <deployment-id> <version>"
  exit 1
fi

DEPLOYMENT_ID=$1
VERSION=$2
REGION=${AWS_REGION:-us-east-1}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPOSITORY_NAME="sd-inference-${DEPLOYMENT_ID}"
IMAGE_TAG="${VERSION}"

# Check if ECR repository exists, create if not
aws ecr describe-repositories --repository-names ${REPOSITORY_NAME} --region ${REGION} || \
  aws ecr create-repository --repository-name ${REPOSITORY_NAME} --region ${REGION}

# Get ECR login
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# Build Docker image
echo "Building Docker image..."
cd ../../server/api-scheduler
docker build -t ${REPOSITORY_NAME}:${IMAGE_TAG} .

# Tag and push image
echo "Tagging and pushing image to ECR..."
docker tag ${REPOSITORY_NAME}:${IMAGE_TAG} ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPOSITORY_NAME}:${IMAGE_TAG}
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPOSITORY_NAME}:${IMAGE_TAG}

# Also tag as latest
docker tag ${REPOSITORY_NAME}:${IMAGE_TAG} ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPOSITORY_NAME}:latest
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPOSITORY_NAME}:latest

echo "Image successfully built and pushed to ECR"
echo "Repository: ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPOSITORY_NAME}"
echo "Tags: ${IMAGE_TAG}, latest"

echo "To deploy this version, run: ./deploy-new-version.sh ${DEPLOYMENT_ID} ${VERSION} --percentage 20"
