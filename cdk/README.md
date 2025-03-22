# Stable Diffusion 推理服务 CDK 部署

这个项目使用 AWS CDK 来部署 Stable Diffusion 推理服务所需的基础设施，包括 API Gateway、Lambda、DynamoDB、SQS、S3 和 CloudFront。

## 特点

- **资源名称唯一化**: 每次部署都会生成唯一的资源名称，允许在同一个 AWS 账号中多次部署
- **一键部署**: 提供简单的部署脚本，自动完成所有步骤
- **完整基础设施**: 包含所有必要的 AWS 资源配置
- **部署管理**: 提供部署、更新、列表和删除脚本，方便管理多个部署

## 前置条件

- Node.js (>= 14.x)
- AWS CLI 已配置
- AWS CDK 已安装 (`npm install -g aws-cdk`)
- TypeScript (`npm install -g typescript`)
- jq (用于列出部署，可选)

## 部署管理脚本

本项目提供了四个管理脚本，方便操作不同的部署：

### 1. 部署新实例 (deploy.sh)

```bash
# 创建新部署（自动生成部署ID）
./deploy.sh

# 使用指定的部署ID创建部署
./deploy.sh my-custom-id
```

部署完成后，部署ID会被保存到 `last_deployment_id.txt` 文件中。

### 2. 更新现有部署 (update.sh)

```bash
# 更新上次部署的实例
./update.sh

# 更新指定部署ID的实例
./update.sh deploy-123456
```

### 3. 列出所有部署 (list-deployments.sh)

```bash
./list-deployments.sh
```

这将显示所有部署的堆栈名称、创建时间和最后更新时间。

### 4. 删除部署 (destroy.sh)

```bash
# 删除上次部署的实例
./destroy.sh

# 删除指定部署ID的实例
./destroy.sh deploy-123456
```

## 手动部署步骤

如果你想手动控制部署过程：

1. 安装依赖

```bash
cd cdk
npm install
```

2. 编译 TypeScript 代码

```bash
npm run build
```

3. 引导 CDK (如果是首次在此 AWS 账户/区域中使用 CDK)

```bash
cdk bootstrap
```

4. 部署堆栈（可以指定自定义的部署 ID）

```bash
cdk deploy --context deploymentId=my-custom-id
```

5. 确认部署

部署过程中，CDK 会请求确认创建 IAM 角色和安全相关资源的权限，输入 'y' 确认。

## 资源说明

此 CDK 项目创建以下资源，所有资源名称都包含唯一的部署 ID：

- **DynamoDB 表**: `sd-tasks-{deploymentId}` - 存储任务信息
- **SQS 队列**: `sd-task-queue-{deploymentId}` - 用于存储待处理的推理任务
- **S3 存储桶**: `sd-images-{deploymentId}-{accountId}` - 存储生成的图片
- **CloudFront 分发**: 提供图片的快速访问
- **Lambda 函数**:
  - `SubmitTaskFunction` - 处理任务提交
  - `TaskInfoFunction` - 查询任务状态
- **API Gateway**: `sdapi-{deploymentId}` - 提供 REST API 接口
  - POST /task: 提交任务
  - GET /task?taskId={id}: 查询任务状态
- **IAM 角色**: `sd-inference-ec2-role-{deploymentId}` - 为 EC2 推理实例提供所需权限

## 多次部署

由于所有资源名称都包含唯一标识符，你可以在同一个 AWS 账号中多次部署此堆栈。每次部署都会创建一组全新的资源，互不干扰。

## 注意事项

- 此部署仅包含基础设施部分，不包括 EC2 Spot Fleet 的配置和自动扩展部分
- 生产环境中应调整资源的删除策略和安全设置
- Lambda 函数代码需要从项目的 `server/lambda` 目录中获取
- 所有脚本都会自动检测和使用 AWS CLI 配置的默认区域
- 如果遇到 "You must specify a region" 错误，请运行 `aws configure` 设置默认区域

## 环境设置

### Node.js 版本要求

AWS CDK 需要 Node.js v18 或 v20 版本。如果您使用的是较旧版本的 Node.js（如 v16），将会收到警告并可能导致部署问题。

### 快速设置

我们提供了一个自动化脚本来设置正确的 Node.js 环境：

```bash
# 设置 Node.js 环境
./setup-node.sh

# 修复安全漏洞
./fix-vulnerabilities.sh
```

### 手动设置

如果您想手动设置环境，请按照以下步骤操作：

1. 安装 nvm (Node Version Manager):
```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
```

2. 加载 nvm (可能需要重新打开终端):
```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
```

3. 安装 Node.js v18:
```bash
nvm install 18
```

4. 使用 Node.js v18:
```bash
nvm use 18
```

5. 设置为默认版本:
```bash
nvm alias default 18
```

### 自动版本检查

所有部署脚本现在都包含 Node.js 版本检查功能，如果检测到不兼容的版本：
- 如果安装了 nvm，脚本会尝试自动切换到 Node.js v18
- 如果没有安装 nvm，脚本会提示您安装合适的版本

## 安全注意事项

项目依赖中存在一些安全漏洞，主要来自于 AWS CDK 相关的库和其他依赖项。为了修复这些漏洞，可以运行提供的修复脚本：

```bash
cd cdk
./fix-vulnerabilities.sh
```

这个脚本会：
1. 更新 AWS CDK 相关依赖到最新版本
2. 更新其他有漏洞的依赖
3. 运行 npm audit fix 尝试自动修复
4. 如果还有高危或严重漏洞，尝试强制修复

请注意，强制更新可能会导致不兼容问题，更新后请确保项目仍然能够正常工作。
