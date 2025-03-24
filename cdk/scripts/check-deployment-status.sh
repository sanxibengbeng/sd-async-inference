#!/bin/bash
set -e

# This script checks the status of a deployment
# Usage: ./check-deployment-status.sh <deployment-id>

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

if [ $# -lt 1 ]; then
  print_message "red" "Usage: $0 <deployment-id>"
  exit 1
fi

DEPLOYMENT_ID=$1
REGION=${AWS_REGION:-us-east-1}
ASG_NAME="sd-inference-${DEPLOYMENT_ID}"
STACK_NAME="SdInferenceStack-${DEPLOYMENT_ID}"

# Check if the stack exists
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &> /dev/null; then
  print_message "red" "Error: Stack $STACK_NAME does not exist"
  exit 1
fi

# Get stack status
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query "Stacks[0].StackStatus" --output text)
print_message "blue" "Stack status: $STACK_STATUS"

# Get deployment status from SSM Parameter
DEPLOYMENT_STATUS=$(aws ssm get-parameter --name "/sd-inference/${DEPLOYMENT_ID}/deployment-status" --region "$REGION" --query "Parameter.Value" --output text 2>/dev/null || echo "unknown")
print_message "blue" "Deployment status: $DEPLOYMENT_STATUS"

# Get current and previous image versions
CURRENT_VERSION=$(aws ssm get-parameter --name "/sd-inference/${DEPLOYMENT_ID}/image-version" --region "$REGION" --query "Parameter.Value" --output text 2>/dev/null || echo "unknown")
PREVIOUS_VERSION=$(aws ssm get-parameter --name "/sd-inference/${DEPLOYMENT_ID}/previous-version" --region "$REGION" --query "Parameter.Value" --output text 2>/dev/null || echo "unknown")
print_message "blue" "Current image version: $CURRENT_VERSION"
print_message "blue" "Previous image version: $PREVIOUS_VERSION"

# Check ASG status
if aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --region "$REGION" &> /dev/null; then
  # Get ASG instance count
  INSTANCE_COUNT=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --region "$REGION" --query "AutoScalingGroups[0].Instances | length(@)" --output text)
  DESIRED_CAPACITY=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --region "$REGION" --query "AutoScalingGroups[0].DesiredCapacity" --output text)
  HEALTHY_COUNT=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --region "$REGION" --query "AutoScalingGroups[0].Instances[?HealthStatus=='Healthy'] | length(@)" --output text)
  
  print_message "blue" "ASG instance count: $INSTANCE_COUNT/$DESIRED_CAPACITY (Healthy: $HEALTHY_COUNT)"
  
  # Check if there's an ongoing instance refresh
  REFRESH_COUNT=$(aws autoscaling describe-instance-refreshes --auto-scaling-group-name "$ASG_NAME" --region "$REGION" --query "length(InstanceRefreshes[?Status=='InProgress' || Status=='Pending'])" --output text)
  
  if [ "$REFRESH_COUNT" -gt 0 ]; then
    print_message "yellow" "Instance refresh in progress"
    
    # Get details of the ongoing refresh
    REFRESH_INFO=$(aws autoscaling describe-instance-refreshes --auto-scaling-group-name "$ASG_NAME" --region "$REGION" --query "InstanceRefreshes[?Status=='InProgress' || Status=='Pending'][0]" --output json)
    
    REFRESH_ID=$(echo "$REFRESH_INFO" | jq -r '.InstanceRefreshId')
    REFRESH_STATUS=$(echo "$REFRESH_INFO" | jq -r '.Status')
    PERCENTAGE_COMPLETE=$(echo "$REFRESH_INFO" | jq -r '.PercentageComplete')
    INSTANCES_REPLACED=$(echo "$REFRESH_INFO" | jq -r '.InstancesToUpdate')
    
    print_message "blue" "Refresh ID: $REFRESH_ID"
    print_message "blue" "Status: $REFRESH_STATUS"
    print_message "blue" "Progress: $PERCENTAGE_COMPLETE%"
    print_message "blue" "Instances to update: $INSTANCES_REPLACED"
  else
    print_message "green" "No instance refresh in progress"
  fi
  
  # List instances with their status
  print_message "blue" "Instance details:"
  aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG_NAME" --region "$REGION" --query "AutoScalingGroups[0].Instances[*].[InstanceId, HealthStatus, LifecycleState]" --output table
  
else
  print_message "yellow" "Auto Scaling Group $ASG_NAME not found"
fi

# Check SQS queue status
QUEUE_URL=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" --query "Stacks[0].Outputs[?OutputKey=='TaskQueueUrl'].OutputValue" --output text 2>/dev/null || echo "")

if [ -n "$QUEUE_URL" ]; then
  QUEUE_MESSAGES=$(aws sqs get-queue-attributes --queue-url "$QUEUE_URL" --attribute-names ApproximateNumberOfMessages --region "$REGION" --query "Attributes.ApproximateNumberOfMessages" --output text)
  QUEUE_MESSAGES_IN_FLIGHT=$(aws sqs get-queue-attributes --queue-url "$QUEUE_URL" --attribute-names ApproximateNumberOfMessagesNotVisible --region "$REGION" --query "Attributes.ApproximateNumberOfMessagesNotVisible" --output text)
  
  print_message "blue" "SQS queue messages: $QUEUE_MESSAGES (In flight: $QUEUE_MESSAGES_IN_FLIGHT)"
else
  print_message "yellow" "SQS queue URL not found"
fi

# Check CloudWatch alarms
print_message "blue" "CloudWatch alarms status:"
aws cloudwatch describe-alarms --region "$REGION" --query "MetricAlarms[?Dimensions[?Value=='${ASG_NAME}' || Value=='${STACK_NAME}']].[AlarmName, StateValue, StateReason]" --output table

print_message "green" "Deployment status check completed"
