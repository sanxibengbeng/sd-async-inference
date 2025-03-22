#!/bin/bash

# 检查 Node.js 版本
check_node_version() {
    NODE_VERSION=$(node -v | cut -d 'v' -f 2)
    MAJOR_VERSION=$(echo $NODE_VERSION | cut -d '.' -f 1)

    if [ $MAJOR_VERSION -lt 18 ]; then
        echo "警告: 当前 Node.js 版本 ($NODE_VERSION) 不受支持"
        echo "AWS CDK 需要 Node.js v18 或 v20"
        
        # 如果安装了 nvm，尝试切换版本
        if command -v nvm &> /dev/null; then
            echo "检测到 nvm，尝试切换到 Node.js v18..."
            nvm use 18 || nvm install 18
            
            # 再次检查版本
            NODE_VERSION=$(node -v | cut -d 'v' -f 2)
            MAJOR_VERSION=$(echo $NODE_VERSION | cut -d '.' -f 1)
            
            if [ $MAJOR_VERSION -lt 18 ]; then
                echo "错误: 无法切换到 Node.js v18，请手动安装合适的版本"
                return 1
            else
                echo "成功切换到 Node.js $(node -v)"
                return 0
            fi
        else
            echo "请安装 Node.js v18 或更高版本后再运行此脚本"
            echo "建议使用 nvm 进行安装: https://github.com/nvm-sh/nvm"
            echo "安装命令: curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"
            echo "安装后运行: nvm install 18 && nvm use 18"
            return 1
        fi
    fi
    return 0
}
