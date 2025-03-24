#!/bin/bash

# 检查 Node.js 版本
check_node_version() {
    NODE_VERSION=$(node -v | cut -d 'v' -f 2)
    MAJOR_VERSION=$(echo $NODE_VERSION | cut -d '.' -f 1)

    if [ $MAJOR_VERSION -lt 16 ]; then
        echo "警告: 当前 Node.js 版本 ($NODE_VERSION) 较旧"
        echo "推荐使用 Node.js v18 或 v20，但 v16 也可以尝试使用"
        
        # 询问用户是否继续
        read -p "是否继续使用当前版本? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "操作已取消"
            return 1
        fi
    elif [ $MAJOR_VERSION -lt 18 ]; then
        echo "警告: 当前 Node.js 版本 ($NODE_VERSION) 不是最佳选择"
        echo "AWS CDK 推荐使用 Node.js v18 或 v20，但将尝试使用当前版本"
        echo "如果遇到问题，请考虑升级 Node.js 版本"
        
        # 如果安装了 nvm，提示可以切换版本
        if command -v nvm &> /dev/null; then
            echo "检测到 nvm，您可以运行以下命令切换版本:"
            echo "nvm install 18 && nvm use 18"
            
            # 询问用户是否切换
            read -p "是否现在切换到 Node.js v18? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                nvm use 18 || nvm install 18
                
                # 再次检查版本
                NODE_VERSION=$(node -v | cut -d 'v' -f 2)
                MAJOR_VERSION=$(echo $NODE_VERSION | cut -d '.' -f 1)
                
                if [ $MAJOR_VERSION -lt 18 ]; then
                    echo "错误: 无法切换到 Node.js v18，将继续使用当前版本"
                else
                    echo "成功切换到 Node.js $(node -v)"
                fi
            fi
        fi
    fi
    return 0
}
