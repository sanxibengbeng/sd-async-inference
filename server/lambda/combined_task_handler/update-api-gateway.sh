#!/bin/bash

# 确保脚本在出错时停止执行
set -e

echo "开始更新 API Gateway 配置..."

# 检查是否提供了API Gateway ID
if [ -z "$1" ]; then
  echo "错误: 缺少必要参数"
  echo "用法: ./update-api-gateway.sh <API Gateway ID>"
  exit 1
fi

API_ID=$1
FUNCTION_NAME="combined-task-handler"
REGION=$(aws configure get region)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
LAMBDA_ARN="arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$FUNCTION_NAME"

# 获取API Gateway资源
echo "获取API Gateway资源..."
RESOURCES=$(aws apigateway get-resources --rest-api-id $API_ID --region $REGION)
ROOT_ID=$(echo $RESOURCES | jq -r '.items[] | select(.path=="/") | .id')

# 检查/task资源是否存在
TASK_RESOURCE_ID=$(echo $RESOURCES | jq -r '.items[] | select(.path=="/task") | .id')

if [ "$TASK_RESOURCE_ID" == "" ]; then
  echo "创建/task资源..."
  TASK_RESOURCE=$(aws apigateway create-resource \
    --rest-api-id $API_ID \
    --parent-id $ROOT_ID \
    --path-part "task" \
    --region $REGION)
  TASK_RESOURCE_ID=$(echo $TASK_RESOURCE | jq -r '.id')
else
  echo "使用现有/task资源..."
fi

# 配置GET方法
echo "配置GET方法..."
aws apigateway put-method \
  --rest-api-id $API_ID \
  --resource-id $TASK_RESOURCE_ID \
  --http-method GET \
  --authorization-type NONE \
  --region $REGION || true

aws apigateway put-integration \
  --rest-api-id $API_ID \
  --resource-id $TASK_RESOURCE_ID \
  --http-method GET \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri "arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/$LAMBDA_ARN/invocations" \
  --region $REGION || true

# 配置POST方法
echo "配置POST方法..."
aws apigateway put-method \
  --rest-api-id $API_ID \
  --resource-id $TASK_RESOURCE_ID \
  --http-method POST \
  --authorization-type NONE \
  --region $REGION || true

aws apigateway put-integration \
  --rest-api-id $API_ID \
  --resource-id $TASK_RESOURCE_ID \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri "arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/$LAMBDA_ARN/invocations" \
  --region $REGION || true

# 添加Lambda权限
echo "添加Lambda权限..."
aws lambda add-permission \
  --function-name $FUNCTION_NAME \
  --statement-id apigateway-get \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*/GET/task" \
  --region $REGION || true

aws lambda add-permission \
  --function-name $FUNCTION_NAME \
  --statement-id apigateway-post \
  --action lambda:InvokeFunction \
  --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*/POST/task" \
  --region $REGION || true

# 部署API
echo "部署API..."
aws apigateway create-deployment \
  --rest-api-id $API_ID \
  --stage-name prod \
  --region $REGION

echo "API Gateway 配置更新完成！"
echo "API 端点: https://$API_ID.execute-api.$REGION.amazonaws.com/prod/task"
