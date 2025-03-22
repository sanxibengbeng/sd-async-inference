#!/bin/bash

# 确保脚本在出错时停止执行
set -e

echo "查询 Stable Diffusion 推理服务部署..."

# 获取 AWS 区域
AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
    echo "错误: 未配置 AWS 区域，请运行 'aws configure' 设置默认区域"
    exit 1
fi

# 检查 AWS 配置
if ! aws sts get-caller-identity &> /dev/null; then
    echo "错误: AWS 凭证未配置或无效，请运行 'aws configure' 进行配置"
    exit 1
fi

# 获取当前部署ID（如果存在）
DEPLOY_ID_FILE="./last_deployment_id.txt"
CURRENT_DEPLOYMENT=""
if [ -f "$DEPLOY_ID_FILE" ]; then
    CURRENT_DEPLOYMENT=$(cat $DEPLOY_ID_FILE)
    echo "当前活跃部署ID: $CURRENT_DEPLOYMENT"
    echo ""
fi

# 列出所有相关的 CloudFormation 堆栈
echo "所有 Stable Diffusion 部署:"
echo "----------------------------------------"
aws cloudformation list-stacks --region $AWS_REGION --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE | \
    jq -r '.StackSummaries[] | select(.StackName | startswith("SdInferenceStack")) | 
    {StackName, CreationTime, LastUpdatedTime} | 
    "\(.StackName) | 创建时间: \(.CreationTime) | 最后更新: \(.LastUpdatedTime // "未更新")"' | \
    sort

echo ""
echo "要获取特定部署的详细信息，请运行:"
echo "aws cloudformation describe-stacks --stack-name <堆栈名称> --region $AWS_REGION"
echo ""
echo "要使用特定部署，请运行:"
echo "./update.sh <部署ID>"
