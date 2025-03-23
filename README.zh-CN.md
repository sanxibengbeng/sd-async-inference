# Stable Diffusion 异步推理服务

[![en](https://img.shields.io/badge/lang-English-blue.svg)](README.md)
[![zh-cn](https://img.shields.io/badge/语言-中文-red.svg)](README.zh-CN.md)

基于大模型进行图片推理是一个耗时且消耗资源的过程，让业务健康运转，能在可控成本下满足弹性变化的用户流量非常重要。针对这个问题，该项目通过构建可以弹性伸缩的异步推理集群，提供了一个可行的解决方案。

## 快速开始

使用AWS CDK是部署此解决方案的最快方式：

```bash
# 克隆代码库
git clone https://github.com/yourusername/sd-async-inference.git
cd sd-async-inference/cdk

# 安装依赖
npm install

# 部署基础设施
./deploy.sh
```

有关详细的部署说明，请参阅[CDK部署指南](./cdk/README.zh-CN.md)。

## 架构
![架构图](assets/architecture.png)

本方案基于AWS基础服务搭建：
- Amazon API Gateway
- AWS Lambda
- Amazon SQS
- Amazon S3
- Amazon DynamoDB
- Amazon EC2 Spot Fleet

该架构遵循异步处理模式：
1. 客户端通过API Gateway提交推理任务
2. Lambda处理请求并将任务存储在SQS和DynamoDB中
3. 基于EC2的推理集群从SQS处理任务
4. 结果存储在S3中并通过CloudFront访问
5. 基于SQS队列指标进行自动扩缩

## API文档

成功部署后，将提供以下API：

### 提交任务 (POST /task)
```bash
curl -X POST https://${APIGatewayID}.execute-api.${region}.amazonaws.com/task \
  -H "Content-Type: application/json" \
  -d '{"api":"/sdapi/v1/txt2img","payload":{"prompt":"您的提示词","steps":20}}'
```

### 查询任务状态 (GET /task)
```bash
GET https://${APIGatewayID}.execute-api.${region}.amazonaws.com/task?taskId=${taskId}
```

## 项目结构
- `cdk/`: AWS CDK基础设施代码和部署脚本
- `server/`: 服务端组件
  - `lambda/`: Lambda函数代码
  - `api-scheduler/`: 推理任务调度器
- `assets/`: 项目资源文件
- `docs/`: 额外文档

## 贡献
欢迎提交Pull Request或Issue来帮助改进项目。

## 许可证
本项目采用MIT许可证。
