## 介绍
基于大模型进行图片推理是一个耗时且消耗资源的，让业务要健康运转，能在可控成本下满足弹性变化的用户流量非常重要。针对这个问题，该项目通过构建可以弹性伸缩的异步推理集群，提供了一个可行的解决方案。

本方案基于AWS基础服务搭建，主要涉及到以下服务：
- Amazon API Gateway
- AWS Lambda
- Amazon SQS
- Amazon S3
- Amazon DynamoDB
## 架构
  ![Architecture](assets/architecture.png)
- 该方案利用Amazon API Gateway 接受客户端请求，并将请求转发到基于Lambda实现的后端服务；
- AWS Lambda 中目前实现两个业务逻辑：提交任务和查询任务状态；
- Lambda接受任务后会将任务同时写入SQS 和 DynamoDB；
- 基于Spot Fleet 实现的推理集群会从SQS中获取推理任务，完成推理，将结果计入S3，并将结果写回DynamoDB；
- 图片结果存储到S3后，会提供cloudfront访问链接给用户；
- S3也可以作为模型和配置文件的公共存储，在弹性扩容机器时，保障拉取到同样的配置；

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
1. 创建DynamoDB表
2. 创建SQS任务队列
3. 创建S3 Bucket，并配置CloudFront；
4. 创建IAM Role 并配置，授权给EC2实例访问SQS、DynamoDB、S3的权限；
### 一、应用服务部署，AWS Lambda 部署
1. 通用部署步骤：
   - 在本地安装Node.js
   - 获取源码，并打包Lambda代码
   - 上传Lambda代码并配置环境变量，修改IAM角色
   - 创建并绑定API Gateway

### 二、GPU推理实例建设及推理池部署
1. 在AWS EC2 上配置运行stablediffusion webui ，启动命令添加 --api参数
2. 将代码库中 server/api-scheduler 部分拉到服务器上，配置启动；
3. 基于这个实例构建自定义AMI,并配置Spot Fleet；
4. 基于SQS 监控指标和Spot Fleet API 动态控制推理集群大小；