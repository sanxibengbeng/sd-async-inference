#!/bin/bash

# 确保脚本在出错时停止执行
set -e

# 导入 Node.js 版本检查函数
source "$(dirname "$0")/node-version-check.sh"

echo "开始修复 CDK 项目中的安全漏洞..."

# 检查 Node.js 版本
echo "检查 Node.js 版本..."
check_node_version || {
  echo "错误: 需要 Node.js v18 或 v20 才能继续修复漏洞"
  exit 1
}

# 显示当前使用的 Node.js 版本
echo "使用 Node.js $(node -v) 进行修复"

# 更新 AWS CDK 相关依赖到最新版本
echo "更新 AWS CDK 依赖到最新版本..."
npm install --save aws-cdk-lib@latest
npm install --save-dev aws-cdk@latest

# 更新其他有漏洞的依赖
echo "更新其他有漏洞的依赖..."
npm update

# 运行 npm audit fix 尝试自动修复
echo "运行 npm audit fix..."
npm audit fix

# 如果还有高危或严重漏洞，尝试强制修复
echo "检查是否还有高危或严重漏洞..."
if npm audit | grep -E "high|critical"; then
  echo "尝试强制修复高危和严重漏洞..."
  npm audit fix --force
fi

# 最终验证
echo "验证修复结果..."
npm audit

echo "安全漏洞修复完成。请检查项目是否正常工作。"
