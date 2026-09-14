# 全功能多语言远端开发环境 (Debian 12 Bookworm)

专为 **本地 VS Code 客户端 Remote-SSH 远程开发** 与 **DeepSeek AI Agent (dsh) 协作** 精心设计的全栈 Docker 开发容器。

采用官方镜像多阶段精细拼接架构，完美支持 **GitHub Actions 云端自动化多架构（x86_64 + ARM64）编译** 并自动发布至 GitHub Container Registry。内置 Go、Rust、Node.js、Python 最新语言环境，预装 Git、OpenSSH-Server 以及 DeepSeek Harness (`dsh`) CLI 及其两款官方实验团队插件。

---

## 目录与项目结构

```text
.
├── Dockerfile                  # 基于 Debian 12 + 官方多阶段拼接的 Docker 构建文件
├── docker-compose.yml          # 一键编排文件 (默认直接拉取 GHCR 云端镜像)
├── entrypoint.sh               # 容器入口管理脚本 (缓存初始化、SSH 密钥持久化、服务启动)
├── .env.example                # 环境变量配置模板
├── .dockerignore               # Docker 构建上下文忽略清单
├── .gitignore                  # Git 忽略配置 (保护 API Key、私钥与工作区)
├── .github/
│   └── workflows/
│       └── docker-build.yml    # GitHub Actions 云端双架构自动构建与发布流水线
├── dsh/                        # 挂载到容器内 /root/.dsh 的 DSH 配置与运行数据目录 (宿主机直读直改)
└── workspace/                  # 挂载到容器内 /workspace 的代码工作区目录
```

---

## 核心设计特性

### 1. 为什么无需 Web 版 code-server？
- **本地 VS Code 客户端负责一切 UI**：您在本地电脑打开 VS Code，通过 Remote-SSH 连接容器。连上瞬间，本地客户端会自动将轻量级无头 `vscode-server` 投送至容器内运行。
- **极致轻量高效**：剔除沉重的 Web 版 VS Code 后，镜像体积缩减，且构建速度大幅提升，容器运行时资源 100% 留给编译器与 AI Agent。
- **官方 API 动态预置**：Dockerfile 在构建时会自动查询微软官方最新 Stable Commit 并预置 VS Code Server 核心，首次连接秒开，彻底告别“Downloading VS Code Server”卡顿。

### 2. DSH 配置与数据独立挂载
- **宿主机目录直通**：容器将 `/root/.dsh` 完整挂载到宿主机 `./dsh` 目录。
- **预装实验团队插件**：镜像构建期已预装 `@deepseek-ai/dsh-experimental-agent-team-profile` 与 `@deepseek-ai/dsh-experimental-agent-team-web-profile` 两款官方实验团队插件。首次运行容器时，会自动将插件配置模板初始化同步至宿主机 `./dsh` 目录中。
- **便捷改配**：所有 DSH 生成的配置文件（如 `settings.yaml`、模型列表、API Key 配置、智能体会话数据）都在宿主机 `./dsh/` 中，您可以直接使用桌面编辑器查看与修改，无需 `docker exec` 进入容器。
- **安全防泄露**：`.gitignore` 已默认排除 `dsh/*`（保留说明文件），杜绝个人 API Key 与会话历史意外推送到 GitHub。

### 3. 多语言官方镜像无缝拼接
- **Go 环境**：直接从官方 `golang:bookworm` 提取 `/usr/local/go`。
- **Rust 环境**：直接从官方 `rust:bookworm` 提取最新稳定版 `rustup`、`rustc`、`cargo`。
- **Node.js 环境**：直接从官方 `node:24-bookworm-slim` 提取完整 Node.js 24 LTS 环境，支持 `npm`、`pnpm`、`yarn`。
- **Python 环境**：直接从 Astral 官方镜像提取 `uv` / `uvx`，秒级安装独立 Python 3.13 与 `pip`、`ipython`。

## 持久化目录与存储分流

| 挂载类型 | 宿主机路径 / 卷名 | 容器内路径 | 作用说明 |
| :--- | :--- | :--- | :--- |
| **Bind Mount** | `./workspace` | `/workspace` | **项目源码工作区**，您的所有开发代码存放于此 |
| **Bind Mount** | `./dsh` | `/root/.dsh` | **DSH 配置与数据**，包含 `settings.yaml`、API Key、会话记录，可在宿主机直接编辑 |
| **Named Volume** | `dev_cache` | `/cache` | **开发缓存卷**，统一持久化 Go 模块、Cargo Crates、NPM/Pip/UV 依赖缓存及 SSH Host Key |

---

## 快速使用指引

### 1. 配置环境变量 (可选)
复制环境变量模板（默认 SSH 端口为 `2222`，默认密码为 `dev123456`）：
```bash
cp .env.example .env
```
如需免密直连，可将本地电脑的公钥内容（`~/.ssh/id_rsa.pub`）填入 `.env` 中的 `SSH_PUBLIC_KEY` 变量。

### 2. 一键拉取并启动
由于已接入 GHCR 云编译镜像，本地无需等待耗时的编译，直接拉取即可秒级启动：
```bash
# 拉取最新云端预构建镜像
docker compose pull

# 后台启动开发环境
docker compose up -d
```
> **提示**：如需在本地离线二次开发或自行构建镜像，只需编辑 `docker-compose.yml`，解除 `build:` 部分的注释即可。

### 3. 连接开发环境

#### 步骤一：本地桌面版 VS Code Remote-SSH 直连
在本地桌面 VS Code 安装官方插件 **Remote - SSH**。编辑本地 `~/.ssh/config` 文件并添加：
```ssh
Host dshoer-dev
    HostName 127.0.0.1
    Port 2222
    User root
```
在 VS Code 中点击左下角 `><` 打开远程窗口，选择 `Connect to Host...` -> `dshoer-dev`，输入密码（默认 `dev123456`）即可秒级连入容器！

#### 步骤二：使用 DeepSeek Harness (dsh web)
- 连接 Remote-SSH 后，VS Code 会**自动侦测到容器内的 3080 端口并安全映射至本地**。
- 打开本地浏览器访问 `http://127.0.0.1:3080` 即可进入 DSH 界面。
- **配置模型与密钥**：在 DSH 界面右上角设置中填入您的 DeepSeek API Key，保存后将自动持久化至宿主机的 `./dsh` 目录。
- **宿主机直接改配**：您也可以随时直接打开宿主机的 `./dsh` 文件夹对配置文件进行查看或微调。

---

## 容器内部管理命令

```bash
# 查看容器运行状态
docker compose ps

# 查看容器启动日志 (包含 DSH 访问 Token 与状态)
docker compose logs -f

# 进入容器交互终端
docker exec -it full-dev-env bash

# 停止开发环境
docker compose down
```
