# dshoer

## 项目结构

```text
.
├── Dockerfile                  # 多语言环境构建文件 (Debian 12 + 官方多阶段拼接)
├── docker-compose.yml          # 一键编排启动文件
├── entrypoint.sh               # 容器初始化入口脚本
├── updsh.sh                    # 容器内 DSH 一键升级与重载工具
├── .env.example                # 环境变量配置模板
└── .github/workflows/
    └── docker-build.yml        # GitHub Actions 云端双架构自动构建流水线
```

## 配置与启动

1. 编辑 `docker-compose.yml` 填入您的 SSH 公钥及 Git 身份（可选）：
```yaml
environment:
  SSH_PUBLIC_KEY: "ssh-ed25519 AAAAC3NzaC... 你的公钥"
  GIT_USER_NAME: ""
  GIT_USER_EMAIL: ""
```

2. 启动容器：
```bash
docker compose pull
docker compose up -d
```


## 常用管理命令

```bash
# 进入容器交互终端
docker exec -it full-dev-env bash

# 容器内一键更新 DSH (平滑重载，无需重启整个 Docker)
updsh                    # 升级至最新稳定版 (latest)
updsh next               # 升级至最新预览分支 (next)
updsh 0.1.7-rc.2         # 升级至指定版本号

# 登录 GitHub (免密 Push 代码)
gh auth login

# 停止开发环境
docker compose down
```
