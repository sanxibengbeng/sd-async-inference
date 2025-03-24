#!/bin/bash
set -e

# This script implements a gradual deployment with canary testing and rollback capability
# Usage: ./deploy-new-version.sh <deployment-id> <new-version> [--percentage <percentage>] [--wait]

# Function: display colored messages
print_message() {
  local color=$1
  local message=$2
  case $color in
    "green") echo -e "\033[0;32m$message\033[0m" ;;
    "red") echo -e "\033[0;31m$message\033[0m" ;;
    "yellow") echo -e "\033[0;33m$message\033[0m" ;;
    "blue") echo -e "\033[0;34m$message\033[0m" ;;
    *) echo "$message" ;;
  esac
}

# Function: log messages
log() {
  local message=$1
  local log_file="deploy_${DEPLOYMENT_ID}_$(date +%Y%m%d_%H%M%S).log"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$log_file"
}

# Function: handle errors
handle_error() {
  local exit_code=$?
  print_message "red" "Error: Deployment failed with exit code $exit_code"
  log "Error: Deployment failed with exit code $exit_code"
  
  if [ "$AUTO_ROLLBACK" = true ]; then
    print_message "yellow" "Auto-rollback enabled, rolling back to previous version: ${CURRENT_VERSION}"
    log "Auto-rollback enabled, rolling back to previous version: ${CURRENT_VERSION}"
    
    # Update deployment status to rolling-back
    aws ssm put-parameter --name "/sd-inference/${DEPLOYMENT_ID}/deployment-status" --value "rolling-back" --type "String" --overwrite --region ${REGION}
    
    # Update the image version parameter to previous version
    aws ssm put-parameter --name "/sd-inference/${DEPLOYMENT_ID}/image-version" --value "${CURRENT_VERSION}" --type "String" --overwrite --region ${REGION}
    
    # Start instance refresh for rollback
    ROLLBACK_REFRESH_ID=$(aws autoscaling start-instance-refresh \
      --auto-scaling-group-name ${ASG_NAME} \
      --region ${REGION} \
      --preferences "{\"MinHealthyPercentage\": 90, \"InstanceWarmup\": 300}" \
      --strategy "Rolling" \
      --query "InstanceRefreshId" \
      --output text)
      
    print_message "yellow" "Started rollback with refresh ID: ${ROLLBACK_REFRESH_ID}"
    log "Started rollback with refresh ID: ${ROLLBACK_REFRESH_ID}"
  fi
  
  exit $exit_code
}

# Set up error handling
trap handle_error ERR

if [ $# -lt 2 ]; then
  print_message "red" "Usage: $0 <deployment-id> <new-version> [--percentage <percentage>] [--wait] [--no-rollback]"
  exit 1
fi

DEPLOYMENT_ID=$1
NEW_VERSION=$2
PERCENTAGE=20  # Default percentage for canary deployment
WAIT=false     # Default: don't wait for completion
AUTO_ROLLBACK=true # Default: auto-rollback on failure

# Parse optional arguments
shift 2
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --percentage)
      PERCENTAGE="$2"
      shift 2
      ;;
    --wait)
      WAIT=true
      shift
      ;;
    --no-rollback)
      AUTO_ROLLBACK=false
      shift
      ;;
    *)
      print_message "red" "Unknown option: $1"
      exit 1
      ;;
  esac
done

REGION=${AWS_REGION:-us-east-1}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPOSITORY_NAME="sd-inference-${DEPLOYMENT_ID}"
ASG_NAME="sd-inference-${DEPLOYMENT_ID}"

log "Starting deployment for ${DEPLOYMENT_ID}, new version: ${NEW_VERSION}, percentage: ${PERCENTAGE}%"

# Validate percentage
if ! [[ "$PERCENTAGE" =~ ^[0-9]+$ ]] || [ "$PERCENTAGE" -lt 1 ] || [ "$PERCENTAGE" -gt 100 ]; then
  print_message "red" "Error: Percentage must be an integer between 1 and 100"
  log "Error: Percentage must be an integer between 1 and 100"
  exit 1
fi

# Check if the ECR repository exists
if ! aws ecr describe-repositories --repository-names ${REPOSITORY_NAME} --region ${REGION} &> /dev/null; then
  print_message "red" "Error: ECR repository ${REPOSITORY_NAME} does not exist"
  log "Error: ECR repository ${REPOSITORY_NAME} does not exist"
  exit 1
fi

# Check if the image exists
if ! aws ecr describe-images --repository-name ${REPOSITORY_NAME} --image-ids imageTag=${NEW_VERSION} --region ${REGION} &> /dev/null; then
  print_message "red" "Error: Image ${REPOSITORY_NAME}:${NEW_VERSION} does not exist in ECR"
  log "Error: Image ${REPOSITORY_NAME}:${NEW_VERSION} does not exist in ECR"
  exit 1
fi

# Check if ASG exists
if ! aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${ASG_NAME} --region ${REGION} &> /dev/null; then
  print_message "red" "Error: Auto Scaling Group ${ASG_NAME} does not exist"
  log "Error: Auto Scaling Group ${ASG_NAME} does not exist"
  exit 1
fi

# Check if there's already an instance refresh in progress
REFRESH_IN_PROGRESS=$(aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name ${ASG_NAME} \
  --region ${REGION} \
  --query "length(InstanceRefreshes[?Status=='InProgress' || Status=='Pending'])" \
  --output text)

if [ "$REFRESH_IN_PROGRESS" -gt 0 ]; then
  print_message "red" "Error: There is already an instance refresh in progress for ASG ${ASG_NAME}"
  log "Error: There is already an instance refresh in progress for ASG ${ASG_NAME}"
  exit 1
fi

# Check current deployment status
DEPLOYMENT_STATUS=$(aws ssm get-parameter --name "/sd-inference/${DEPLOYMENT_ID}/deployment-status" --region ${REGION} --query "Parameter.Value" --output text 2>/dev/null || echo "unknown")
if [ "$DEPLOYMENT_STATUS" != "stable" ]; then
  print_message "yellow" "Warning: Current deployment status is ${DEPLOYMENT_STATUS}, not stable"
  log "Warning: Current deployment status is ${DEPLOYMENT_STATUS}, not stable"
  
  # Ask for confirmation
  read -p "Do you want to proceed with the deployment anyway? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_message "red" "Deployment aborted"
    log "Deployment aborted by user"
    exit 1
  fi
fi

# Get current version and store it as previous version for potential rollback
CURRENT_VERSION=$(aws ssm get-parameter --name "/sd-inference/${DEPLOYMENT_ID}/image-version" --region ${REGION} --query "Parameter.Value" --output text)
print_message "blue" "Current version: ${CURRENT_VERSION}"
print_message "blue" "New version: ${NEW_VERSION}"
log "Current version: ${CURRENT_VERSION}, New version: ${NEW_VERSION}"

# Store the current version as previous version for rollback
aws ssm put-parameter --name "/sd-inference/${DEPLOYMENT_ID}/previous-version" --value "${CURRENT_VERSION}" --type "String" --overwrite --region ${REGION}
log "Stored current version as previous version for rollback"

# Update deployment status to in-progress
aws ssm put-parameter --name "/sd-inference/${DEPLOYMENT_ID}/deployment-status" --value "in-progress" --type "String" --overwrite --region ${REGION}
log "Updated deployment status to in-progress"

# Update the image version parameter
aws ssm put-parameter --name "/sd-inference/${DEPLOYMENT_ID}/image-version" --value "${NEW_VERSION}" --type "String" --overwrite --region ${REGION}
log "Updated image version parameter to ${NEW_VERSION}"

# Get current instance count
INSTANCE_COUNT=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${ASG_NAME} --region ${REGION} --query "AutoScalingGroups[0].DesiredCapacity" --output text)
print_message "blue" "Current instance count: ${INSTANCE_COUNT}"
log "Current instance count: ${INSTANCE_COUNT}"

# Calculate number of instances to update in this batch
INSTANCES_TO_UPDATE=$(( ($INSTANCE_COUNT * $PERCENTAGE) / 100 ))
if [ $INSTANCES_TO_UPDATE -lt 1 ]; then
  INSTANCES_TO_UPDATE=1
fi
print_message "blue" "Updating ${INSTANCES_TO_UPDATE} instances (${PERCENTAGE}% of total)"
log "Updating ${INSTANCES_TO_UPDATE} instances (${PERCENTAGE}% of total)"

# Start instance refresh with percentage-based batch size
REFRESH_ID=$(aws autoscaling start-instance-refresh \
  --auto-scaling-group-name ${ASG_NAME} \
  --region ${REGION} \
  --preferences "{\"MinHealthyPercentage\": 90, \"InstanceWarmup\": 300, \"MaxHealthyPercentage\": 100, \"ScaleInProtectedInstances\": \"Ignore\", \"StandbyInstances\": \"Ignore\"}" \
  --strategy "Rolling" \
  --desired-configuration "{\"LaunchTemplate\":{\"LaunchTemplateName\":\"${ASG_NAME}\",\"Version\":\"\$Latest\"}}" \
  --query "InstanceRefreshId" \
  --output text)

print_message "green" "Started instance refresh with ID: ${REFRESH_ID}"
log "Started instance refresh with ID: ${REFRESH_ID}"

if [ "$WAIT" = true ]; then
  print_message "blue" "Waiting for deployment to complete..."
  log "Waiting for deployment to complete..."
  
  # Monitor the instance refresh
  STATUS="Pending"
  while [ "$STATUS" == "Pending" ] || [ "$STATUS" == "InProgress" ]; do
    sleep 30
    REFRESH_INFO=$(aws autoscaling describe-instance-refreshes \
      --auto-scaling-group-name ${ASG_NAME} \
      --instance-refresh-ids ${REFRESH_ID} \
      --region ${REGION})
    
    STATUS=$(echo $REFRESH_INFO | jq -r '.InstanceRefreshes[0].Status')
    PERCENTAGE_COMPLETE=$(echo $REFRESH_INFO | jq -r '.InstanceRefreshes[0].PercentageComplete')
    INSTANCES_REPLACED=$(echo $REFRESH_INFO | jq -r '.InstanceRefreshes[0].InstancesToUpdate')
    
    print_message "blue" "Status: $STATUS, Progress: $PERCENTAGE_COMPLETE%, Instances replaced: $INSTANCES_REPLACED"
    log "Status: $STATUS, Progress: $PERCENTAGE_COMPLETE%, Instances replaced: $INSTANCES_REPLACED"
    
    # Check if there are any failures
    if [ "$STATUS" == "Failed" ]; then
      FAILURE_REASON=$(echo $REFRESH_INFO | jq -r '.InstanceRefreshes[0].StatusReason')
      print_message "red" "Deployment failed: $FAILURE_REASON"
      log "Deployment failed: $FAILURE_REASON"
      
      if [ "$AUTO_ROLLBACK" = true ]; then
        print_message "yellow" "Rolling back to previous version: ${CURRENT_VERSION}"
        log "Rolling back to previous version: ${CURRENT_VERSION}"
        
        # Update deployment status to rolling-back
        aws ssm put-parameter --name "/sd-inference/${DEPLOYMENT_ID}/deployment-status" --value "rolling-back" --type "String" --overwrite --region ${REGION}
        
        # Update the image version parameter to previous version
        aws ssm put-parameter --name "/sd-inference/${DEPLOYMENT_ID}/image-version" --value "${CURRENT_VERSION}" --type "String" --overwrite --region ${REGION}
        
        # Start a new instance refresh to roll back
        ROLLBACK_REFRESH_ID=$(aws autoscaling start-instance-refresh \
          --auto-scaling-group-name ${ASG_NAME} \
          --region ${REGION} \
          --preferences "{\"MinHealthyPercentage\": 90, \"InstanceWarmup\": 300}" \
          --strategy "Rolling" \
          --query "InstanceRefreshId" \
          --output text)
          
        print_message "yellow" "Started rollback with refresh ID: ${ROLLBACK_REFRESH_ID}"
        log "Started rollback with refresh ID: ${ROLLBACK_REFRESH_ID}"
      fi
      
      exit 1
    fi
  done

  if [ "$STATUS" == "Successful" ]; then
    print_message "green" "Deployment completed successfully!"
    log "Deployment completed successfully!"
    aws ssm put-parameter --name "/sd-inference/${DEPLOYMENT_ID}/deployment-status" --value "stable" --type "String" --overwrite --region ${REGION}
    log "Updated deployment status to stable"
  else
    print_message "yellow" "Deployment ended with status: $STATUS"
    log "Deployment ended with status: $STATUS"
    exit 1
  fi
else
  print_message "blue" "Deployment started. Use './check-deployment-status.sh ${DEPLOYMENT_ID}' to monitor progress."
  log "Deployment started in non-waiting mode. User should monitor progress manually."
fi

print_message "green" "Deployment process initiated successfully"
log "Deployment process initiated successfully"
