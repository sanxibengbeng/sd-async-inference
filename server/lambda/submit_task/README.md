# 功能介绍
submit_task 主要提供实现接收客户端提交的任务的能力。主要逻辑代码在index.mjs中，接收到客户端请求之后，submit_task 会执行以下主要步骤：
1. 生成唯一taskID，用于标识这次推理任务；
2. 将任务请求信息写入DynamoDB表；
3. 将taskID及任务存储在DynamoDB中这个信息写入到SQS，供下游服务拉取；

# 部署说明
1. 编译安装依赖获得lambda代码压缩文件包
   ``` bash
   cd server/lambda/submit_task 
   npm install
   zip -r submit_task.zip
   ```
1. 在 AWS console, 创建名为 ***submit_task*** 的Lambda function 
    > 如果是在Mac M1/M2 芯片机器上构建，则需要设置cpu架构为arm64

2. 将submit_task.zip 上传到lambda

4. 配置API Gateway 转发请求到lambda