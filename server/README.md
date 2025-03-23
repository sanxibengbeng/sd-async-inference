# Stable Diffusion 异步推理服务端组件

本目录包含 Stable Diffusion 异步推理服务的服务端组件，分为两个主要部分：

## 1. Lambda 函数 (task_handler)

位于 `lambda/task_handler` 目录，这是一个 Node.js Lambda 函数，负责：

- 接收并处理客户端的推理任务请求
- 将任务信息存储到 DynamoDB
- 将任务发送到 SQS 队列
- 提供任务状态查询接口

详细信息请参阅 [Lambda 函数文档](./lambda/task_handler/README.md)

## 2. API 调度器 (api-scheduler)

位于 `api-scheduler` 目录，这是一个 Python 应用程序，运行在 EC2 实例上，负责：

- 从 SQS 队列获取推理任务
- 调用本地运行的 Stable Diffusion WebUI API
- 将生成的图片上传到 S3
- 更新 DynamoDB 中的任务状态
- 根据队列长度自动扩缩 EC2 实例数量

详细信息请参阅 [API 调度器文档](./api-scheduler/README.md)

## 部署流程

1. 首先使用 CDK 部署基础设施（API Gateway、Lambda、DynamoDB、SQS、S3、CloudFront）
2. 然后在 EC2 实例上部署 Stable Diffusion WebUI 和 API 调度器
3. 配置 API 调度器连接到 SQS、DynamoDB 和 S3

## 系统架构

服务端组件在整个系统中的位置如下：

```
客户端 → API Gateway → Lambda 函数 → SQS → API 调度器 → Stable Diffusion WebUI
                                      ↓
                                  DynamoDB ← API 调度器 → S3 → CloudFront → 客户端
```

# Server Components for Stable Diffusion Async Inference

This directory contains the server-side components of the Stable Diffusion async inference service, divided into two main parts:

## 1. Lambda Function (task_handler)

Located in the `lambda/task_handler` directory, this Node.js Lambda function is responsible for:

- Receiving and processing inference task requests from clients
- Storing task information in DynamoDB
- Sending tasks to the SQS queue
- Providing task status query interface

For detailed information, please refer to the [Lambda Function Documentation](./lambda/task_handler/README.md)

## 2. API Scheduler (api-scheduler)

Located in the `api-scheduler` directory, this Python application runs on EC2 instances and is responsible for:

- Retrieving inference tasks from the SQS queue
- Calling the locally running Stable Diffusion WebUI API
- Uploading generated images to S3
- Updating task status in DynamoDB
- Automatically scaling EC2 instances based on queue length

For detailed information, please refer to the [API Scheduler Documentation](./api-scheduler/README.md)

## Deployment Process

1. First, deploy the infrastructure using CDK (API Gateway, Lambda, DynamoDB, SQS, S3, CloudFront)
2. Then deploy Stable Diffusion WebUI and API Scheduler on EC2 instances
3. Configure the API Scheduler to connect to SQS, DynamoDB, and S3

## System Architecture

The position of server components in the overall system:

```
Client → API Gateway → Lambda Function → SQS → API Scheduler → Stable Diffusion WebUI
                                        ↓
                                    DynamoDB ← API Scheduler → S3 → CloudFront → Client
```
