# 合并任务处理器 Lambda 函数

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

## 部署步骤

1. 安装依赖:
   ```bash
   npm install
   ```

2. 打包 Lambda 函数:
   ```bash
   zip -r combined_task_handler.zip index.mjs node_modules package.json
   ```

3. 创建 Lambda 函数:
   ```bash
   aws lambda create-function \
     --function-name combined-task-handler \
     --runtime nodejs18.x \
     --handler index.handler \
     --zip-file fileb://combined_task_handler.zip \
     --role <Lambda执行角色ARN> \
     --environment Variables="{DYNAMODB_TABLE=sd_tasks,QUEUE_URL=<SQS队列URL>}"
   ```

4. 配置 API Gateway:
   - 创建 API Gateway REST API
   - 创建资源 `/task`
   - 为该资源添加 GET 和 POST 方法
   - 将两个方法都集成到同一个 Lambda 函数

## 环境变量

- `DYNAMODB_TABLE`: DynamoDB 表名 (默认: "sd_tasks")
- `QUEUE_URL`: SQS 队列 URL

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

## 注意事项

- 确保 Lambda 函数有足够的权限访问 DynamoDB 和 SQS
- 考虑为不同的操作设置不同的超时时间
- 监控函数的执行时间和内存使用情况，根据需要调整配置
