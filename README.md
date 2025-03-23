# Stable Diffusion 异步推理服务

基于大模型进行图片推理是一个耗时且消耗资源的过程，让业务健康运转，能在可控成本下满足弹性变化的用户流量非常重要。针对这个问题，该项目通过构建可以弹性伸缩的异步推理集群，提供了一个可行的解决方案。

## 介绍

本方案基于 AWS 基础服务搭建，主要涉及到以下服务：
- Amazon API Gateway
- AWS Lambda
- Amazon SQS
- Amazon S3
- Amazon DynamoDB

## 架构
![Architecture](assets/architecture.png)

- 该方案利用 Amazon API Gateway 接受客户端请求，并将请求转发到基于 Lambda 实现的后端服务；
- AWS Lambda 中实现业务逻辑：处理任务提交和查询任务状态；
- Lambda 接受任务后会将任务同时写入 SQS 和 DynamoDB；
- 基于 Spot Fleet 实现的推理集群会从 SQS 中获取推理任务，完成推理，将结果存入 S3，并将结果写回 DynamoDB；
- 图片结果存储到 S3 后，会提供 CloudFront 访问链接给用户；
- S3 也可以作为模型和配置文件的公共存储，在弹性扩容机器时，保障拉取到同样的配置；

## 前置需求
- AWS Account: 操作用户需要具备创建相关服务的权限；

## 接口说明
本方案部署成功后，会获得如下接口：
1. POST /task 提交任务, 请求样例如下
   ```bash
   curl -X POST https://${APIGatewayID}.execute-api.${region}.amazonaws.com/task \
      -H "Content-Type: application/json" \
   -d '{"api":"/sdapi/v1/txt2img","payload":{"prompt":"(masterpiece), (extremely intricate:1.3), (realistic), portrait of a girl, the most beautiful in the world, (medieval armor), metal reflections, upper body, outdoors, intense sunlight, far away castle, professional photograph of a stunning woman detailed, sharp focus, dramatic, award winning, cinematic lighting, octane render  unreal engine,  volumetrics dtx, (film grain, blurry background, blurry foreground, bokeh, depth of field, sunset, motion blur:1.3), chainmail","steps":20}}'
   ```

2. Get /task 获取任务状态查询任务结果, 请求样例如下

   ```bash
   GET https://${APIGatewayID}.execute-api.${region}.amazonaws.com/task?taskId=${taskId}
   ```

## 方案部署
### 前置准备
1. 创建 DynamoDB 表 表名：sd_tasks， 分区键设置为 taskId 字符串 类型；
2. 创建 SQS 任务队列，标准型即可；
3. 创建 S3 Bucket，并配置 CloudFront；
4. 创建 IAM Role 并配置，授权给 EC2 实例访问 SQS、DynamoDB、S3 的权限；

### 一、应用服务部署，AWS Lambda 部署
1. 部署 APIGateWay，创建名为 sdapi 的 APIGateway，并创建路由：
   1）GET /task 用于获取任务详情
   2）POST /task 用于提交任务
2. 部署应用函数
   [部署 task_handler](./server/lambda/task_handler/README.md)

### 二、GPU 推理实例建设及推理池部署
1. 在 AWS EC2 上配置运行 Stable Diffusion WebUI，启动命令添加 --api 参数
2. 将代码库中 server/api-scheduler 部分拉到服务器上，配置启动；
3. 基于这个实例构建自定义 AMI，并配置 Spot Fleet；
4. 基于 SQS 监控指标和 Spot Fleet API 动态控制推理集群大小；

## 项目结构
- `cdk/`: AWS CDK 基础设施代码
- `server/`: 服务端组件
  - `lambda/`: Lambda 函数代码
  - `api-scheduler/`: 推理任务调度器
- `assets/`: 项目资源文件

## 贡献指南
欢迎提交 Pull Request 或 Issue 来帮助改进项目。

## 许可证
本项目采用 MIT 许可证。

# Stable Diffusion Asynchronous Inference Service

Image inference based on large models is a time-consuming and resource-intensive process. For businesses to operate healthily and meet elastic user traffic under controllable costs, this project provides a viable solution by building an elastically scalable asynchronous inference cluster.

## Introduction

This solution is built on AWS foundational services, primarily involving the following services:
- Amazon API Gateway
- AWS Lambda
- Amazon SQS
- Amazon S3
- Amazon DynamoDB

## Architecture
![Architecture](assets/architecture.png)

- The solution uses Amazon API Gateway to accept client requests and forward them to backend services implemented with Lambda;
- AWS Lambda implements business logic: handling task submission and querying task status;
- After Lambda accepts a task, it writes the task to both SQS and DynamoDB;
- The inference cluster implemented with Spot Fleet retrieves inference tasks from SQS, completes inference, stores results in S3, and writes results back to DynamoDB;
- After image results are stored in S3, CloudFront access links are provided to users;
- S3 can also serve as public storage for models and configuration files, ensuring the same configuration is pulled during elastic scaling;

## Prerequisites
- AWS Account: Users need permissions to create related services;

## API Documentation
After successful deployment, the following interfaces will be available:
1. POST /task to submit tasks, request example:
   ```bash
   curl -X POST https://${APIGatewayID}.execute-api.${region}.amazonaws.com/task \
      -H "Content-Type: application/json" \
   -d '{"api":"/sdapi/v1/txt2img","payload":{"prompt":"(masterpiece), (extremely intricate:1.3), (realistic), portrait of a girl, the most beautiful in the world, (medieval armor), metal reflections, upper body, outdoors, intense sunlight, far away castle, professional photograph of a stunning woman detailed, sharp focus, dramatic, award winning, cinematic lighting, octane render  unreal engine,  volumetrics dtx, (film grain, blurry background, blurry foreground, bokeh, depth of field, sunset, motion blur:1.3), chainmail","steps":20}}'
   ```

2. GET /task to query task status and results, request example:

   ```bash
   GET https://${APIGatewayID}.execute-api.${region}.amazonaws.com/task?taskId=${taskId}
   ```

## Deployment
### Prerequisites
1. Create a DynamoDB table named sd_tasks with partition key taskId of string type;
2. Create a standard SQS task queue;
3. Create an S3 Bucket and configure CloudFront;
4. Create and configure an IAM Role, granting EC2 instances permissions to access SQS, DynamoDB, and S3;

### Part 1: Application Service Deployment, AWS Lambda Deployment
1. Deploy APIGateway, create an APIGateway named sdapi, and create routes:
   1) GET /task for retrieving task details
   2) POST /task for submitting tasks
2. Deploy application functions
   [Deploy task_handler](./server/lambda/task_handler/README.md)

### Part 2: GPU Inference Instance Setup and Inference Pool Deployment
1. Configure and run Stable Diffusion WebUI on AWS EC2, add --api parameter to the startup command
2. Pull the server/api-scheduler part from the code repository to the server and configure startup;
3. Build a custom AMI based on this instance and configure Spot Fleet;
4. Dynamically control inference cluster size based on SQS monitoring metrics and Spot Fleet API;

## Project Structure
- `cdk/`: AWS CDK infrastructure code
- `server/`: Server-side components
  - `lambda/`: Lambda function code
  - `api-scheduler/`: Inference task scheduler
- `assets/`: Project resource files

## Contribution Guidelines
Pull Requests or Issues are welcome to help improve the project.

## License
This project is licensed under the MIT License.
