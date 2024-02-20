# 功能介绍
task_info 主要提供实现接收客户端提交的任务的能力。主要逻辑代码在index.mjs中，接收到客户端请求之后，task_info 会执行以下主要步骤：
1. 生成唯一taskID，用于标识这次推理任务；
2. 将任务请求信息写入DynamoDB表；
3. 将taskID及任务存储在DynamoDB中这个信息写入到SQS，供下游服务拉取；

# 部署说明
1. 编译安装依赖获得lambda代码压缩文件包
   ``` bash
   cd server/lambda/task_info 
   npm install
   zip -r task_info.zip ./*
   ```
1. 在 AWS console, 创建名为 ***task_info*** 的Lambda function 
    重点关注：
    > 如果是在Mac M1/M2 芯片机器上构建，则需要设置cpu架构为arm64 

2. 将task_info.zip 上传到lambda
3. 配置环境变量：
   1) DYNAMODB_TABLE ： 表名，如果不配置，默认是sd_tasks
4. 配置权限：在 Lambda IAM Role里授予DynamoDB的读取权限
5. 配置API Gateway 将GET /task 转发请求到lambda