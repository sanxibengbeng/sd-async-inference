#!/bin/bash

# 确保脚本在出错时停止执行
set -e

echo "开始测试合并任务处理器 API..."

# 检查是否提供了API Gateway URL
if [ -z "$1" ]; then
  echo "错误: 缺少必要参数"
  echo "用法: ./test.sh <API Gateway URL>"
  echo "例如: ./test.sh https://abc123def.execute-api.us-east-1.amazonaws.com/prod/task"
  exit 1
fi

API_URL=$1

# 提交任务测试
echo "测试提交任务 (POST /task)..."
RESPONSE=$(curl -s -X POST $API_URL \
  -H "Content-Type: application/json" \
  -d '{"api":"/sdapi/v1/txt2img","payload":{"prompt":"test prompt","steps":5}}')

echo "提交任务响应:"
echo $RESPONSE | jq .

# 提取任务ID
TASK_ID=$(echo $RESPONSE | jq -r '.taskId')

if [ "$TASK_ID" == "null" ] || [ -z "$TASK_ID" ]; then
  echo "错误: 无法获取任务ID"
  exit 1
fi

echo "获取到任务ID: $TASK_ID"

# 等待几秒钟
echo "等待3秒..."
sleep 3

# 查询任务测试
echo "测试查询任务 (GET /task?taskId=$TASK_ID)..."
QUERY_RESPONSE=$(curl -s -X GET "$API_URL?taskId=$TASK_ID")

echo "查询任务响应:"
echo $QUERY_RESPONSE | jq .

echo "测试完成！"
