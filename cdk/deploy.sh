#!/bin/bash

# 确保脚本在出错时停止执行
set -e

# 部署ID文件
DEPLOY_ID_FILE="./last_deployment_id.txt"

# 检查是否提供了部署ID参数
if [ -z "$1" ]; then
  # 如果没有提供参数，生成新的部署ID
  DEPLOYMENT_ID="deploy-$(date +%s | tail -c 7)"
  echo "生成新的部署ID: $DEPLOYMENT_ID"
else
  DEPLOYMENT_ID=$1
  echo "使用指定的部署ID: $DEPLOYMENT_ID"
fi

echo "开始部署 Stable Diffusion 推理服务... 部署ID: $DEPLOYMENT_ID"

# 检查是否安装了必要的工具
if ! command -v npm &> /dev/null; then
    echo "错误: 未安装 npm，请先安装 Node.js"
    exit 1
fi

if ! command -v cdk &> /dev/null; then
    echo "安装 AWS CDK..."
    npm install -g aws-cdk
fi

# 获取 AWS 区域
AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
    echo "错误: 未配置 AWS 区域，请运行 'aws configure' 设置默认区域"
    exit 1
fi

# 安装依赖
echo "安装项目依赖..."
npm install

# 编译 TypeScript 代码
echo "编译 TypeScript 代码..."
npm run build

# 检查 AWS 配置
echo "检查 AWS 配置..."
if ! aws sts get-caller-identity &> /dev/null; then
    echo "错误: AWS 凭证未配置或无效，请运行 'aws configure' 进行配置"
    exit 1
fi

# 引导 CDK (如果需要)
echo "引导 CDK 环境..."
cdk bootstrap --region $AWS_REGION

# 部署堆栈
echo "部署 CDK 堆栈..."
cdk deploy --context deploymentId=$DEPLOYMENT_ID --require-approval never --region $AWS_REGION

# 保存部署ID到文件
echo $DEPLOYMENT_ID > $DEPLOY_ID_FILE
echo "部署ID已保存到 $DEPLOY_ID_FILE"

echo "部署完成！请查看上面的输出获取资源信息。"
echo "部署ID: $DEPLOYMENT_ID"
echo "AWS 区域: $AWS_REGION"
