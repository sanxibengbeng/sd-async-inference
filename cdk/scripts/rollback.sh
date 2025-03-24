#!/bin/bash
set -e

# This script rolls back to the previous stable version
# Usage: ./rollback.sh <deployment-id> [--wait]

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
  local log_file="rollback_${DEPLOYMENT_ID}_$(date +%Y%m%d_%H%M%S).log"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$log_file"
}

# Function: handle errors
handle_error() {
  local exit_code=$?
  print_message "red" "Error: Rollback failed with exit code $exit_code"
  log "Error: Rollback failed with exit code $exit_code"
  exit $exit_code
}

# Set up error handling
trap handle_error ERR

if [ $# -lt 1 ]; then
  print_message "red" "Usage: $0 <deployment-id> [--wait]"
  exit 1
fi

DEPLOYMENT_ID=$1
WAIT=false

# Parse optional arguments
shift
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --wait)
      WAIT=true
      shift
      ;;
    *)
      print_message "red" "Unknown option: $1"
      exit 1
      ;;
  esac
done

REGION=${AWS_REGION:-us-east-1}
ASG_NAME="sd-inference-${DEPLOYMENT_ID}"

log "Starting rollback for deployment ${DEPLOYMENT_ID}"

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
  print_message "yellow" "Warning: There is already an instance refresh in progress for ASG ${ASG_NAME}"
  log "Warning: There is already an instance refresh in progress for ASG ${ASG_NAME}"
  
  # Ask for confirmation
  read -p "Do you want to cancel the current refresh and start rollback? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_message "red" "Rollback aborted"
    log "Rollback aborted by user"
    exit 1
  fi
  
  # Get the refresh ID
  CURRENT_REFRESH_ID=$(aws autoscaling describe-instance-refreshes \
    --auto-scaling-group-name ${ASG_NAME} \
    --region ${REGION} \
    --query "InstanceRefreshes[?Status=='InProgress' || Status=='Pending'][0].InstanceRefreshId" \
    --output text)
  
  # Cancel the current refresh
  aws autoscaling cancel-instance-refresh \
    --auto-scaling-group-name ${ASG_NAME} \
    --region ${REGION}
  
  print_message "yellow" "Cancelled instance refresh ${CURRENT_REFRESH_ID}"
  log "Cancelled instance refresh ${CURRENT_REFRESH_ID}"
  
  # Wait a moment for the cancellation to take effect
  sleep 10
fi

# Get previous and current versions
PREVIOUS_VERSION=$(aws ssm get-parameter --name "/sd-inference/${DEPLOYMENT_ID}/previous-version" --region ${REGION} --query "Parameter.Value" --output text 2>/dev/null || echo "unknown")
CURRENT_VERSION=$(aws ssm get-parameter --name "/sd-inference/${DEPLOYMENT_ID}/image-version" --region ${REGION} --query "Parameter.Value" --output text 2>/dev/null || echo "unknown")

if [ "$PREVIOUS_VERSION" == "unknown" ]; then
  print_message "red" "Error: Could not determine previous version"
  log "Error: Could not determine previous version"
  exit 1
fi

print_message "blue" "Current version: ${CURRENT_VERSION}"
print_message "blue" "Rolling back to previous version: ${PREVIOUS_VERSION}"
log "Current version: ${CURRENT_VERSION}, Rolling back to previous version: ${PREVIOUS_VERSION}"

# Confirm rollback
read -p "Are you sure you want to roll back to version ${PREVIOUS_VERSION}? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  print_message "red" "Rollback aborted"
  log "Rollback aborted by user"
  exit 1
fi

# Update deployment status
aws ssm put-parameter --name "/sd-inference/${DEPLOYMENT_ID}/deployment-status" --value "rolling-back" --type "String" --overwrite --region ${REGION}
log "Updated deployment status to rolling-back"

# Swap current and previous versions
aws ssm put-parameter --name "/sd-inference/${DEPLOYMENT_ID}/previous-version" --value "${CURRENT_VERSION}" --type "String" --overwrite --region ${REGION}
log "Updated previous version parameter to ${CURRENT_VERSION}"

# Update the image version parameter to previous version
aws ssm put-parameter --name "/sd-inference/${DEPLOYMENT_ID}/image-version" --value "${PREVIOUS_VERSION}" --type "String" --overwrite --region ${REGION}
log "Updated image version parameter to ${PREVIOUS_VERSION}"

# Start instance refresh for rollback
REFRESH_ID=$(aws autoscaling start-instance-refresh \
  --auto-scaling-group-name ${ASG_NAME} \
  --region ${REGION} \
  --preferences "{\"MinHealthyPercentage\": 90, \"InstanceWarmup\": 300, \"ScaleInProtectedInstances\": \"Ignore\", \"StandbyInstances\": \"Ignore\"}" \
  --strategy "Rolling" \
  --query "InstanceRefreshId" \
  --output text)

print_message "green" "Started rollback with refresh ID: ${REFRESH_ID}"
log "Started rollback with refresh ID: ${REFRESH_ID}"

if [ "$WAIT" = true ]; then
  print_message "blue" "Waiting for rollback to complete..."
  log "Waiting for rollback to complete..."
  
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
    
    print_message "blue" "Status: $STATUS, Progress: $PERCENTAGE_COMPLETE%"
    log "Status: $STATUS, Progress: $PERCENTAGE_COMPLETE%"
    
    # Check if there are any failures
    if [ "$STATUS" == "Failed" ]; then
      FAILURE_REASON=$(echo $REFRESH_INFO | jq -r '.InstanceRefreshes[0].StatusReason')
      print_message "red" "Rollback failed: $FAILURE_REASON"
      log "Rollback failed: $FAILURE_REASON"
      exit 1
    fi
  done

  if [ "$STATUS" == "Successful" ]; then
    print_message "green" "Rollback completed successfully!"
    log "Rollback completed successfully!"
    aws ssm put-parameter --name "/sd-inference/${DEPLOYMENT_ID}/deployment-status" --value "stable" --type "String" --overwrite --region ${REGION}
    log "Updated deployment status to stable"
  else
    print_message "yellow" "Rollback ended with status: $STATUS"
    log "Rollback ended with status: $STATUS"
    exit 1
  fi
else
  print_message "blue" "Rollback started. Use './check-deployment-status.sh ${DEPLOYMENT_ID}' to monitor progress."
  log "Rollback started in non-waiting mode. User should monitor progress manually."
fi

print_message "green" "Rollback process initiated successfully"
log "Rollback process initiated successfully"
