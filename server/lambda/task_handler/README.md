# 任务处理器 Lambda 函数

这个 Lambda 函数整合了任务提交和任务查询功能，通过一个单一的函数处理两种不同的 API 请求。

## 功能

- **POST /task**: 提交新的推理任务
- **GET /task**: 查询任务状态和结果

## 优势

1. **减少资源开销**: 只需部署和维护一个 Lambda 函数
2. **简化 API 路由**: 通过 HTTP 方法区分操作，而不是不同的端点
3. **代码复用**: 共享 DynamoDB 客户端和配置
4. **一致的错误处理**: 统一的错误处理和响应格式
5. **更容易维护**: 相关功能集中在一个文件中

## 环境变量

- `DYNAMODB_TABLE`: DynamoDB 表名 (默认: "sd_tasks")
- `QUEUE_URL`: SQS 队列 URL
- `CLOUDFRONT_DOMAIN`: CloudFront 分配的域名，用于构建图片 URL

## 请求示例

### 提交任务 (POST /task)

```bash
curl -X POST https://${APIGatewayID}.execute-api.${region}.amazonaws.com/task \
  -H "Content-Type: application/json" \
  -d '{"api":"/sdapi/v1/txt2img","payload":{"prompt":"(masterpiece),...","steps":20}}'
```

### 查询任务 (GET /task)

```bash
curl -X GET https://${APIGatewayID}.execute-api.${region}.amazonaws.com/task?taskId=${taskId}
```

## 部署步骤

1. 安装依赖:
   ```bash
   npm install
   ```

2. 打包 Lambda 函数:
   ```bash
   zip -r function.zip index.js node_modules
   ```

3. 使用 CDK 部署 (推荐):
   ```bash
   # 在项目根目录运行
   cd ../../cdk
   ./deploy.sh
   ```

4. 或者手动创建 Lambda 函数:
   ```bash
   aws lambda create-function \
     --function-name task-handler \
     --runtime nodejs18.x \
     --handler index.handler \
     --zip-file fileb://function.zip \
     --role arn:aws:iam::${ACCOUNT_ID}:role/lambda-execution-role
   ```

## 代码结构

- `index.js`: 主函数入口点，包含路由逻辑
- `package.json`: 项目依赖
- `node_modules/`: 安装的依赖库

## 注意事项

- 确保 Lambda 函数有足够的权限访问 DynamoDB 和 SQS
- 考虑为不同的操作设置不同的超时时间
- 监控函数的执行时间和内存使用情况，根据需要调整配置

# Task Handler Lambda Function

This Lambda function integrates task submission and task query functionality, handling two different API requests through a single function.

## Features

- **POST /task**: Submit new inference tasks
- **GET /task**: Query task status and results

## Advantages

1. **Reduced Resource Overhead**: Only need to deploy and maintain one Lambda function
2. **Simplified API Routing**: Differentiate operations by HTTP method rather than different endpoints
3. **Code Reuse**: Share DynamoDB client and configuration
4. **Consistent Error Handling**: Unified error handling and response format
5. **Easier Maintenance**: Related functionality centralized in one file

## Environment Variables

- `DYNAMODB_TABLE`: DynamoDB table name (default: "sd_tasks")
- `QUEUE_URL`: SQS queue URL
- `CLOUDFRONT_DOMAIN`: CloudFront distribution domain name, used to build image URLs

## Request Examples

### Submit Task (POST /task)

```bash
curl -X POST https://${APIGatewayID}.execute-api.${region}.amazonaws.com/task \
  -H "Content-Type: application/json" \
  -d '{"api":"/sdapi/v1/txt2img","payload":{"prompt":"(masterpiece),...","steps":20}}'
```

### Query Task (GET /task)

```bash
curl -X GET https://${APIGatewayID}.execute-api.${region}.amazonaws.com/task?taskId=${taskId}
```

## Deployment Steps

1. Install dependencies:
   ```bash
   npm install
   ```

2. Package the Lambda function:
   ```bash
   zip -r function.zip index.js node_modules
   ```

3. Deploy using CDK (recommended):
   ```bash
   # Run from project root
   cd ../../cdk
   ./deploy.sh
   ```

4. Or manually create Lambda function:
   ```bash
   aws lambda create-function \
     --function-name task-handler \
     --runtime nodejs18.x \
     --handler index.handler \
     --zip-file fileb://function.zip \
     --role arn:aws:iam::${ACCOUNT_ID}:role/lambda-execution-role
   ```

## Code Structure

- `index.js`: Main function entry point, contains routing logic
- `package.json`: Project dependencies
- `node_modules/`: Installed dependency libraries

## Considerations

- Ensure the Lambda function has sufficient permissions to access DynamoDB and SQS
- Consider setting different timeout values for different operations
- Monitor function execution time and memory usage, adjust configuration as needed
