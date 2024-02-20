
# 前置要求
1. 安装supervisor pip3 install supervisor

# 部署api-scheduler
1. 执行命令 ```cp conf.template.ini conf.ini```
2. 将conf.ini修改为自己的配置信息

# 同机部署stablediffusion webui
1. 基于AWS DeepLearning AMI 启动 g4dn.xlarge (如果选择其他AMI需要自己安装驱动)
2. git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui
2. 


# 开发指南
本项目基于poetry构建，参考以下文档学习poetry项目开发相关指令
1. [poetry doc](https://github.com/python-poetry/poetry)
2. [poetry cheat sheet](https://www.yippeecode.com/topics/python-poetry-cheat-sheet/)
