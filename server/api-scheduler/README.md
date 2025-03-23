# API 调度器 (API Scheduler)

API 调度器是 Stable Diffusion 异步推理服务的核心组件，负责从 SQS 队列获取任务，调用 Stable Diffusion WebUI API，并将结果存储到 S3 和 DynamoDB。

## 前置要求

1. Python 3.8+
2. 安装 supervisor: `pip3 install supervisor`
3. 安装 Poetry: `curl -sSL https://install.python-poetry.org | python3 -`
4. AWS 凭证配置（用于访问 SQS、DynamoDB 和 S3）

## 部署步骤

### 1. 配置文件设置

1. 创建配置文件：
   ```bash
   cp conf.template.ini conf.ini
   ```

2. 编辑 `conf.ini` 文件，设置以下参数：
   - `sqs_queue_url`: SQS 队列 URL
   - `dynamodb_table`: DynamoDB 表名
   - `s3_bucket`: S3 存储桶名称
   - `cloudfront_domain`: CloudFront 域名
   - `sd_api_base_url`: Stable Diffusion WebUI API 地址（默认为 http://127.0.0.1:7860）
   - `poll_interval`: 轮询 SQS 队列的间隔（秒）
   - `max_tasks_per_poll`: 每次轮询获取的最大任务数
   - `aws_region`: AWS 区域

### 2. 在 EC2 实例上部署 Stable Diffusion WebUI

1. 基于 AWS Deep Learning AMI 启动 g4dn.xlarge 实例（或其他支持 CUDA 的实例类型）
   ```bash
   # 如果使用其他 AMI，需要安装 NVIDIA 驱动和 CUDA
   ```

2. 克隆 Stable Diffusion WebUI 仓库：
   ```bash
   git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui
   cd stable-diffusion-webui
   ```

3. 启动 WebUI，启用 API：
   ```bash
   ./webui.sh --api
   ```

### 3. 部署 API 调度器

1. 克隆本仓库并进入 api-scheduler 目录：
   ```bash
   git clone https://github.com/yourusername/sd-async-inference.git
   cd sd-async-inference/server/api-scheduler
   ```

2. 安装依赖：
   ```bash
   poetry install
   ```

3. 使用 supervisor 启动服务：
   ```bash
   cd deploy
   supervisord -c supervisord.conf
   ```

4. 检查服务状态：
   ```bash
   supervisorctl status
   ```

## 目录结构

- `scheduler/`: 主要代码目录
  - `main.py`: 入口点
  - `sqs_consumer.py`: SQS 队列消费者
  - `sd_api_client.py`: Stable Diffusion API 客户端
  - `task_processor.py`: 任务处理器
- `deploy/`: 部署相关文件
  - `supervisord/`: Supervisor 配置
  - `run/`: 运行脚本
  - `log/`: 日志目录
- `tests/`: 测试代码
- `conf.template.ini`: 配置模板

## 开发指南

本项目基于 Poetry 构建，参考以下文档学习 Poetry 项目开发相关指令：

1. [Poetry 文档](https://github.com/python-poetry/poetry)
2. [Poetry 速查表](https://www.yippeecode.com/topics/python-poetry-cheat-sheet/)

### 常用命令

```bash
# 安装依赖
poetry install

# 添加新依赖
poetry add package-name

# 运行应用
poetry run python scheduler/main.py

# 运行测试
poetry run pytest
```

## 自动扩缩功能

API 调度器包含一个自动扩缩组件，可以根据 SQS 队列长度自动调整 EC2 Spot Fleet 的目标容量：

1. 当队列长度超过阈值时，增加实例数量
2. 当队列为空且无活跃任务时，减少实例数量
3. 支持设置最小和最大实例数量

配置参数在 `conf.ini` 的 `[autoscaling]` 部分。

# API Scheduler

The API Scheduler is a core component of the Stable Diffusion async inference service, responsible for retrieving tasks from the SQS queue, calling the Stable Diffusion WebUI API, and storing results in S3 and DynamoDB.

## Prerequisites

1. Python 3.8+
2. Install supervisor: `pip3 install supervisor`
3. Install Poetry: `curl -sSL https://install.python-poetry.org | python3 -`
4. AWS credentials configured (for accessing SQS, DynamoDB, and S3)

## Deployment Steps

### 1. Configuration Setup

1. Create a configuration file:
   ```bash
   cp conf.template.ini conf.ini
   ```

2. Edit the `conf.ini` file to set the following parameters:
   - `sqs_queue_url`: SQS queue URL
   - `dynamodb_table`: DynamoDB table name
   - `s3_bucket`: S3 bucket name
   - `cloudfront_domain`: CloudFront domain
   - `sd_api_base_url`: Stable Diffusion WebUI API address (default is http://127.0.0.1:7860)
   - `poll_interval`: Interval for polling the SQS queue (seconds)
   - `max_tasks_per_poll`: Maximum number of tasks to retrieve per poll
   - `aws_region`: AWS region

### 2. Deploy Stable Diffusion WebUI on EC2 Instance

1. Launch a g4dn.xlarge instance (or other CUDA-capable instance type) based on AWS Deep Learning AMI
   ```bash
   # If using another AMI, you need to install NVIDIA drivers and CUDA
   ```

2. Clone the Stable Diffusion WebUI repository:
   ```bash
   git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui
   cd stable-diffusion-webui
   ```

3. Start the WebUI with API enabled:
   ```bash
   ./webui.sh --api
   ```

### 3. Deploy API Scheduler

1. Clone this repository and navigate to the api-scheduler directory:
   ```bash
   git clone https://github.com/yourusername/sd-async-inference.git
   cd sd-async-inference/server/api-scheduler
   ```

2. Install dependencies:
   ```bash
   poetry install
   ```

3. Start the service using supervisor:
   ```bash
   cd deploy
   supervisord -c supervisord.conf
   ```

4. Check service status:
   ```bash
   supervisorctl status
   ```

## Directory Structure

- `scheduler/`: Main code directory
  - `main.py`: Entry point
  - `sqs_consumer.py`: SQS queue consumer
  - `sd_api_client.py`: Stable Diffusion API client
  - `task_processor.py`: Task processor
- `deploy/`: Deployment-related files
  - `supervisord/`: Supervisor configuration
  - `run/`: Run scripts
  - `log/`: Log directory
- `tests/`: Test code
- `conf.template.ini`: Configuration template

## Development Guide

This project is built with Poetry. Refer to the following documentation to learn about Poetry project development commands:

1. [Poetry Documentation](https://github.com/python-poetry/poetry)
2. [Poetry Cheat Sheet](https://www.yippeecode.com/topics/python-poetry-cheat-sheet/)

### Common Commands

```bash
# Install dependencies
poetry install

# Add new dependency
poetry add package-name

# Run application
poetry run python scheduler/main.py

# Run tests
poetry run pytest
```

## Auto-scaling Feature

The API Scheduler includes an auto-scaling component that can automatically adjust the target capacity of EC2 Spot Fleet based on the SQS queue length:

1. Increase instance count when queue length exceeds threshold
2. Decrease instance count when queue is empty and there are no active tasks
3. Support setting minimum and maximum instance counts

Configuration parameters are in the `[autoscaling]` section of `conf.ini`.
