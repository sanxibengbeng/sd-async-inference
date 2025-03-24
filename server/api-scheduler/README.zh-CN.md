# Stable Diffusion 推理服务的 API 调度器

[![en](https://img.shields.io/badge/lang-English-blue.svg)](README.md)
[![zh-cn](https://img.shields.io/badge/语言-中文-red.svg)](README.zh-CN.md)

该组件负责从 SQS 队列处理任务并将其发送到 Stable Diffusion API 进行推理。

## 功能特性

- 处理来自 SQS 队列的任务
- 在 DynamoDB 中更新任务状态
- 将生成的图像上传到 S3
- 为 EC2 Auto Scaling 提供健康检查端点
- 向 Auto Scaling 服务报告实例健康状态

## 配置

根据提供的 `conf.ini.example` 创建 `conf.ini` 文件：

```ini
[aws]
region = us-east-1
queue_url = sd-task-queue-deploymentid
table_name = sd-tasks-deploymentid
bucket_name = sd-images-deploymentid-12345

[api]
port = 8080
workers = 4
```

## 健康检查实现

API 调度器包含健康检查实现，具体功能如下：

1. 在端口 8080 上暴露 `/health` 端点
2. 执行定期健康检查，包括：
   - API 可用性
   - GPU 状态（如适用）
   - 磁盘空间使用情况
   - 内存使用情况
3. 当检测到问题时向 AWS Auto Scaling 报告不健康状态
4. 记录健康检查结果以便监控

## 运行服务

```bash
python3 main.py
```

服务将：
1. 在后台启动健康检查服务
2. 启动用于健康检查端点的 API 服务器
3. 开始处理来自 SQS 队列的消息

## 部署

该服务通常作为 Docker 容器部署在 Auto Scaling Group 中的 EC2 实例上。
部署由 `cdk` 目录中的 CDK 堆栈管理。

有关详细的部署说明，请参阅：
- [EC2 Auto Scaling Group 部署指南](./docs/deployment-guide.zh-CN.md)
- [Dockerfile 文档](./Dockerfile)

## Docker 容器

可以使用提供的 Dockerfile 将服务容器化：

```bash
# 构建 Docker 镜像
docker build -t api-scheduler:latest .

# 运行容器
docker run -p 8080:8080 \
  -v /path/to/config:/app/config \
  -e AWS_REGION=us-east-1 \
  api-scheduler:latest
```

## 相关文档

- [主项目文档](../../README.zh-CN.md)
- [CDK 部署指南](../../cdk/README.zh-CN.md)
- [Lambda 函数文档](../lambda/task_handler/README.md)
