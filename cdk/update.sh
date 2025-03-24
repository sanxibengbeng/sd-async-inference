#!/bin/bash

# 函数：显示带颜色的消息
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

# 创建日志目录
LOG_DIR="./logs"
mkdir -p "$LOG_DIR"

# 函数：记录日志
log() {
  local message=$1
  local log_file="$LOG_DIR/update_$(date +%Y%m%d).log"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$log_file"
}

# 函数：清理临时文件
cleanup() {
  log "执行清理操作..."
  # 添加任何需要清理的临时文件
  # 不删除日志文件，它们现在存储在logs目录中
}

# 函数：错误处理
handle_error() {
  local exit_code=$?
  print_message "red" "错误: 脚本执行失败，退出代码: $exit_code"
  log "错误: 脚本执行失败，退出代码: $exit_code"
  
  # 检查是否有堆栈部署失败
  if [ ! -z "$STACK_NAME" ] && [ ! -z "$AWS_REGION" ]; then
    log "检查堆栈状态..."
    local stack_status=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].StackStatus" --output text 2>/dev/null)
    
    if [[ "$stack_status" == *FAILED* ]]; then
      print_message "red" "堆栈部署失败: $stack_status"
      log "堆栈部署失败: $stack_status"
      
      # 获取失败原因
      local failure_reason=$(aws cloudformation describe-stack-events --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "StackEvents[?ResourceStatus=='UPDATE_FAILED'].ResourceStatusReason" --output text)
      print_message "red" "失败原因: $failure_reason"
      log "失败原因: $failure_reason"
    fi
  fi
  
  cleanup
  exit $exit_code
}

# 设置错误处理
trap handle_error ERR

# 尝试切换到更高版本的 Node.js
setup_nodejs() {
  print_message "blue" "检查 Node.js 版本..."
  local current_version=$(node -v | cut -d 'v' -f 2)
  local major_version=$(echo $current_version | cut -d '.' -f 1)
  
  if [ $major_version -lt 18 ]; then
    print_message "yellow" "当前 Node.js 版本 ($current_version) 较低，尝试切换到更高版本..."
    
    # 检查是否安装了 nvm
    if command -v nvm &> /dev/null || [ -s "$HOME/.nvm/nvm.sh" ]; then
      # 加载 nvm
      export NVM_DIR="$HOME/.nvm"
      [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
      
      # 尝试使用 nvm 切换版本
      if command -v nvm &> /dev/null; then
        print_message "blue" "使用 nvm 切换 Node.js 版本..."
        
        # 检查是否已安装 Node.js 18
        if nvm ls 18 | grep -q "v18"; then
          nvm use 18
        else
          print_message "blue" "安装 Node.js 18..."
          nvm install 18
          nvm use 18
        fi
        
        # 验证版本
        current_version=$(node -v)
        print_message "green" "已切换到 Node.js $current_version"
        return 0
      fi
    fi
    
    # 如果没有 nvm 或切换失败，尝试使用系统的 Node.js
    if command -v node &> /dev/null; then
      print_message "yellow" "无法切换 Node.js 版本，将使用系统当前版本 $(node -v)"
      print_message "yellow" "建议安装 nvm 并使用 Node.js v18 或更高版本"
      print_message "yellow" "可以运行 ./setup-node.sh 进行安装"
      
      # 询问是否继续
      read -p "是否继续使用当前版本? (y/n) " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_message "red" "操作已取消"
        exit 1
      fi
    else
      print_message "red" "错误: 未找到 Node.js"
      exit 1
    fi
  else
    print_message "green" "当前 Node.js 版本 ($current_version) 满足要求"
  fi
}

# 导入 Node.js 版本检查函数
source "$(dirname "$0")/node-version-check.sh" || {
  print_message "red" "错误: 无法导入 node-version-check.sh"
  exit 1
}

# 设置 Node.js 环境
setup_nodejs

# 部署ID文件
DEPLOY_ID_FILE="./last_deployment_id.txt"

# 检查是否提供了部署ID参数
if [ -z "$1" ]; then
  # 如果没有提供参数，尝试从文件读取
  if [ -f "$DEPLOY_ID_FILE" ]; then
    DEPLOYMENT_ID=$(cat $DEPLOY_ID_FILE)
    print_message "blue" "使用上次部署的ID: $DEPLOYMENT_ID"
    log "使用上次部署的ID: $DEPLOYMENT_ID"
  else
    print_message "red" "错误: 未提供部署ID，且找不到上次部署的ID记录"
    print_message "yellow" "用法: ./update.sh [部署ID]"
    exit 1
  fi
else
  DEPLOYMENT_ID=$1
  print_message "blue" "使用指定的部署ID: $DEPLOYMENT_ID"
  log "使用指定的部署ID: $DEPLOYMENT_ID"
fi

print_message "green" "开始更新 Stable Diffusion 推理服务... 部署ID: $DEPLOYMENT_ID"
log "开始更新 Stable Diffusion 推理服务... 部署ID: $DEPLOYMENT_ID"

# 检查是否安装了必要的工具
if ! command -v npm &> /dev/null; then
    print_message "red" "错误: 未安装 npm，请先安装 Node.js"
    exit 1
fi

if ! command -v cdk &> /dev/null; then
    print_message "yellow" "安装 AWS CDK..."
    npm install -g aws-cdk || {
      print_message "red" "错误: 安装 AWS CDK 失败"
      exit 1
    }
fi

# 获取 AWS 区域
AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
    print_message "red" "错误: 未配置 AWS 区域，请运行 'aws configure' 设置默认区域"
    exit 1
fi

# 检查堆栈是否存在
STACK_NAME="SdInferenceStack-${DEPLOYMENT_ID}"
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" &> /dev/null; then
    print_message "red" "错误: 堆栈 $STACK_NAME 不存在，无法更新。请使用 deploy.sh 进行首次部署。"
    exit 1
fi

# 创建备份
print_message "blue" "创建当前堆栈模板备份..."
log "创建当前堆栈模板备份..."
BACKUP_DIR="./backups"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/stack_template_${DEPLOYMENT_ID}_$(date +%Y%m%d_%H%M%S).json"
aws cloudformation get-template --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "TemplateBody" --output json > "$BACKUP_FILE" || {
  print_message "yellow" "警告: 无法创建堆栈模板备份"
  log "警告: 无法创建堆栈模板备份"
}

# 清理旧的构建目录
if [ -d "dist" ]; then
  print_message "blue" "清理旧的构建目录..."
  log "清理旧的构建目录..."
  rm -rf dist
fi

# 安装依赖
print_message "blue" "安装项目依赖..."
log "安装项目依赖..."
npm ci || {
  print_message "yellow" "警告: npm ci 失败，尝试使用 npm install"
  log "警告: npm ci 失败，尝试使用 npm install"
  npm install || {
    print_message "red" "错误: 安装依赖失败"
    exit 1
  }
}

# 编译 TypeScript 代码
print_message "blue" "编译 TypeScript 代码..."
log "编译 TypeScript 代码..."
npm run build || {
  print_message "red" "错误: TypeScript 编译失败"
  exit 1
}

# 检查 AWS 配置
print_message "blue" "检查 AWS 配置..."
log "检查 AWS 配置..."
if ! aws sts get-caller-identity &> /dev/null; then
    print_message "red" "错误: AWS 凭证未配置或无效，请运行 'aws configure' 进行配置"
    exit 1
fi

# 合成堆栈模板进行验证
print_message "blue" "合成并验证 CDK 堆栈..."
log "合成并验证 CDK 堆栈..."
cdk synth --context deploymentId="$DEPLOYMENT_ID" || {
  print_message "red" "错误: CDK 堆栈合成失败"
  exit 1
}

# 部署堆栈
print_message "blue" "更新 CDK 堆栈..."
log "更新 CDK 堆栈..."
cdk deploy --context deploymentId="$DEPLOYMENT_ID" --require-approval never --region "$AWS_REGION" || {
  print_message "red" "错误: CDK 堆栈部署失败"
  exit 1
}

# 验证部署
print_message "blue" "验证部署状态..."
log "验证部署状态..."
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].StackStatus" --output text)
if [[ "$STACK_STATUS" == *COMPLETE ]]; then
  print_message "green" "堆栈更新成功: $STACK_STATUS"
  log "堆栈更新成功: $STACK_STATUS"
else
  print_message "yellow" "警告: 堆栈状态不是预期的完成状态: $STACK_STATUS"
  log "警告: 堆栈状态不是预期的完成状态: $STACK_STATUS"
fi

# 获取并显示输出
print_message "blue" "获取堆栈输出..."
log "获取堆栈输出..."
aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" --query "Stacks[0].Outputs" --output table

print_message "green" "更新完成！请查看上面的输出获取资源信息。"
print_message "blue" "部署ID: $DEPLOYMENT_ID"
print_message "blue" "AWS 区域: $AWS_REGION"
log "更新完成！部署ID: $DEPLOYMENT_ID, AWS 区域: $AWS_REGION"

# 清理
cleanup
