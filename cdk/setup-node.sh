#!/bin/bash

# 确保脚本在出错时停止执行
set -e

echo "设置 Node.js 环境..."

# 检查是否已安装 nvm
if ! command -v nvm &> /dev/null; then
    echo "安装 nvm (Node Version Manager)..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    
    # 加载 nvm
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    
    # 验证 nvm 安装
    if ! command -v nvm &> /dev/null; then
        echo "错误: nvm 安装失败，请手动安装 Node.js v18"
        exit 1
    fi
fi

# 安装 Node.js v18
echo "安装 Node.js v18..."
nvm install 18

# 使用 Node.js v18
echo "切换到 Node.js v18..."
nvm use 18

# 设置为默认版本
echo "设置 Node.js v18 为默认版本..."
nvm alias default 18

# 验证 Node.js 版本
NODE_VERSION=$(node -v)
echo "当前 Node.js 版本: $NODE_VERSION"

echo "Node.js 环境设置完成！"
echo "现在可以运行 ./fix-vulnerabilities.sh 修复安全漏洞"
