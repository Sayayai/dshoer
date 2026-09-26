# dshoer - 远端开发环境与 DeepSeek Harness

专为 **本地 VS Code Remote-SSH 直连开发** 与 **DeepSeek Harness (dsh)** 打造的全栈多语言 Docker 开发环境，支持 GitHub Actions 云端双架构（amd64 / arm64）自动编译与发布。

内置开箱即用环境：**Java 25 (专为 MC MOD 优化)**、**Go**、**Rust**、**Node.js 24**、**Python 3.13**、**Git / GitHub CLI (gh)**、**OpenSSH Server**。

---

## 项目结构

```text
.
├── Dockerfile                  # 基于 Debian 12 的多语言精细拼接构建文件
├── docker-compose.yml          # 本地/服务器一键编排启动文件
├── entrypoint.sh               # 容器初始化入口脚本 (SSH、缓存映射、服务启动)
├── update-dsh.sh               # 容器内 DSH 一键平滑升级与重载工具
├── .env.example                # 环境变量配置模板
└── .github/workflows/
    └── docker-build.yml        # GitHub Actions 原生双架构云端自动构建流水线
```

---

## 快速使用

### 1. 配置并启动
编辑 `docker-compose.yml`，填入您的本机 SSH 公钥：
```yaml
environment:
  SSH_PUBLIC_KEY: "ssh-ed25519 AAAAC3NzaC... 你的公钥"
  GIT_USER_NAME: "YourName"        # 可选，启动自动配置 Git 身份
  GIT_USER_EMAIL: "your@email.com" # 可选
```

后台拉取并启动：
```bash
docker compose pull
docker compose up -d
```

### 2. 连接开发环境
* **VS Code Remote-SSH 直连**：在本地 `~/.ssh/config` 添加：
  ```ssh
  Host dshoer-dev
      HostName <你的服务器IP>
      Port 52333
      User root
  ```
  连接后直接秒进，终端与文件树默认定位在 `/root/workspace`。
* **访问 DSH WebUI**：打开本地浏览器访问 `http://127.0.0.1:3080`（VS Code Remote-SSH 会自动将容器内 3080 端口安全映射至本地）。

---

## 常用管理命令

```bash
# 进入容器交互终端
docker exec -it full-dev-env bash

# 容器内一键更新 DSH (平滑停服、安装更新并自动重启 WebUI)
update-dsh              # 升级至最新稳定版 (latest)
update-dsh next         # 升级至最新预览分支 (next)
update-dsh 0.1.7-rc.2   # 升级至指定版本号

# 终端登录 GitHub (免密 Push 代码)
gh auth login

# 停止开发环境
docker compose down
```
