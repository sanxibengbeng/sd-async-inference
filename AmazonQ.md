# Stable Diffusion Asynchronous Inference Service - EC2 AutoScalingGroup 部署方案

## 架构概述

本方案通过 AWS CDK 实现了一个弹性可扩展的 Stable Diffusion 异步推理集群，主要组件包括：

1. **EC2 AutoScalingGroup**：运行 api-scheduler 服务的实例集群
2. **容器化部署**：使用 Docker 容器运行 api-scheduler 服务
3. **灰度发布机制**：支持按百分比逐步更新实例
4. **回滚机制**：支持一键回滚到上一个稳定版本

## EC2 AutoScalingGroup 部署逻辑

### 1. 基础设施组件

- **VPC 和安全组**：为 EC2 实例提供网络隔离和安全访问控制
- **IAM 角色**：授予 EC2 实例访问 AWS 服务的权限
- **启动模板**：定义 EC2 实例的配置，包括实例类型、AMI、用户数据脚本等
- **自动扩缩组**：根据 SQS 队列深度自动调整实例数量

### 2. 实例配置

- 使用 GPU 实例 (g4dn.xlarge) 进行高效推理
- 通过用户数据脚本自动配置实例：
  - 安装必要的软件包
  - 配置 CloudWatch 代理
  - 从 ECR 拉取指定版本的 Docker 镜像
  - 配置和启动 api-scheduler 服务

### 3. 自动扩缩策略

- 基于 SQS 队列深度进行扩缩：
  - 队列消息 < 10：保持当前容量
  - 队列消息 10-50：增加 1 个实例
  - 队列消息 50-100：增加 2 个实例
  - 队列消息 > 100：增加 3 个实例
- 队列为空时自动缩减实例数量

## 镜像更新与灰度发布机制

### 1. 镜像构建和推送

- 使用 Docker 构建 api-scheduler 镜像
- 将镜像推送到 Amazon ECR
- 支持版本化管理，每个版本有唯一标识

### 2. 版本追踪

- 使用 SSM Parameter Store 存储当前镜像版本
- 存储上一个稳定版本，用于回滚
- 记录部署状态（稳定、部署中、回滚中）

### 3. 灰度发布流程

- **构建镜像**：构建并推送新版本镜像到 ECR
- **灰度部署**：按指定百分比更新实例
  - 更新 SSM 参数中的镜像版本
  - 触发 AutoScalingGroup 的 Instance Refresh
  - 监控部署进度和健康状态
- **自动回滚**：如果部署失败，自动回滚到上一个稳定版本
- **手动回滚**：提供脚本支持手动回滚操作

## 健康检查与监控

- **应用健康检查**：定期检查 API 服务是否正常响应
- **CloudWatch 监控**：收集实例和应用的关键指标
- **日志管理**：将应用日志和健康检查日志发送到 CloudWatch Logs
- **部署状态追踪**：通过 SSM 参数记录和查询部署状态

## 使用方法

### 部署基础设施

```bash
cd cdk
npm install
./deploy.sh
```

### 构建和推送新镜像

```bash
cd cdk/scripts
./build-and-push-image.sh <deployment-id> <version>
```

### 灰度发布新版本

```bash
cd cdk/scripts
./deploy-new-version.sh <deployment-id> <version> --percentage 20
```

### 回滚到上一个稳定版本

```bash
cd cdk/scripts
./rollback.sh <deployment-id>
```

## 最佳实践

1. **高可用性**：灰度发布确保服务不中断
2. **成本优化**：基于队列深度自动扩缩
3. **可观测性**：完善的监控和日志记录
4. **安全性**：最小权限 IAM 策略和网络隔离
5. **灰度发布**：控制发布风险，支持快速回滚
6. **容器化部署**：标准化运行环境，简化部署流程
