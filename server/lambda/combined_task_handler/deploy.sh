#!/bin/bash

# 确保脚本在出错时停止执行
set -e

echo "开始部署合并任务处理器 Lambda 函数..."

# 安装依赖
echo "安装依赖..."
npm install

# 创建部署包
echo "创建部署包..."
zip -r combined_task_handler.zip index.mjs node_modules package.json

# 检查是否提供了角色ARN和队列URL
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "错误: 缺少必要参数"
  echo "用法: ./deploy.sh <Lambda执行角色ARN> <SQS队列URL>"
  exit 1
fi

ROLE_ARN=$1
QUEUE_URL=$2
FUNCTION_NAME="combined-task-handler"
REGION=$(aws configure get region)

# 检查函数是否已存在
echo "检查函数是否已存在..."
if aws lambda get-function --function-name $FUNCTION_NAME --region $REGION &> /dev/null; then
  echo "更新现有函数..."
  aws lambda update-function-code \
    --function-name $FUNCTION_NAME \
    --zip-file fileb://combined_task_handler.zip \
    --region $REGION

  aws lambda update-function-configuration \
    --function-name $FUNCTION_NAME \
    --environment "Variables={DYNAMODB_TABLE=sd_tasks,QUEUE_URL=$QUEUE_URL}" \
    --region $REGION
else
  echo "创建新函数..."
  aws lambda create-function \
    --function-name $FUNCTION_NAME \
    --runtime nodejs18.x \
    --handler index.handler \
    --zip-file fileb://combined_task_handler.zip \
    --role $ROLE_ARN \
    --environment "Variables={DYNAMODB_TABLE=sd_tasks,QUEUE_URL=$QUEUE_URL}" \
    --region $REGION
fi

echo "部署完成！"
echo "函数名称: $FUNCTION_NAME"
echo "区域: $REGION"
echo ""
echo "接下来需要配置 API Gateway 将 GET 和 POST 请求路由到此函数"
