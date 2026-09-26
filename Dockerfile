# ==============================================================================
# 全功能多语言远端开发环境 Dockerfile (Debian 12 Bookworm)
# 架构: 官方镜像精细拼接 + 极简 SSH 远端开发 (无冗余 Web VSCode)
# 针对 GitHub Actions 多架构 (linux/amd64, linux/arm64) 云编译极速优化
# ==============================================================================

# 阶段 1: 提取官方 Go 工具链
FROM golang:bookworm AS go-source

# 阶段 2: 提取官方 Rust 工具链 (rustup, rustc, cargo)
FROM rust:bookworm AS rust-source

# 阶段 3: 提取官方 Node.js 24 LTS
FROM node:24-bookworm-slim AS node-source

# 阶段 4: 提取官方 Eclipse Temurin OpenJDK 25
FROM eclipse-temurin:25-jdk AS java-source

# ------------------------------------------------------------------------------
# 主阶段: 最终运行镜像
# ------------------------------------------------------------------------------
FROM debian:bookworm-slim

LABEL maintainer="developer"
LABEL description="Lean Multi-arch Remote Dev Container with Go, Rust, Node, Python, Java 25, SSH, and DeepSeek Harness"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# 1. 基础系统与开发工具链 (包含 OpenSSH-Server 与 GitHub CLI)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    gnupg \
    git \
    git-lfs \
    gh \
    build-essential \
    pkg-config \
    libssl-dev \
    jq \
    sudo \
    zsh \
    procps \
    unzip \
    tar \
    xz-utils \
    openssh-server \
    openssh-client \
    rsync \
    net-tools \
    iproute2 \
    python3 \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# 2. 统一全局环境变量与多语言缓存路径
ENV WORKSPACE=/root/workspace \
    CACHE_DIR=/cache \
    JAVA_HOME=/opt/java/openjdk \
    GRADLE_USER_HOME=/cache/gradle \
    GOROOT=/usr/local/go \
    GOPATH=/cache/go \
    GOCACHE=/cache/go/build \
    GOMODCACHE=/cache/go/pkg/mod \
    RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PIP_CACHE_DIR=/cache/pip \
    UV_CACHE_DIR=/cache/uv \
    YARN_CACHE_FOLDER=/cache/yarn \
    PNPM_HOME=/cache/pnpm \
    DSH_HOME=/root/.dsh

ENV PATH=/root/workspace/.bin:$JAVA_HOME/bin:/usr/local/cargo/bin:/cache/cargo/bin:/usr/local/go/bin:/cache/go/bin:/usr/local/bin:/usr/bin:/bin:$PATH

# 3. [官方镜像拼接] 注入 Go 运行时
COPY --from=go-source /usr/local/go /usr/local/go

# 4. [官方镜像拼接] 注入 Rust 运行时 (rustc, cargo, rustup)
COPY --from=rust-source /usr/local/cargo /usr/local/cargo
COPY --from=rust-source /usr/local/rustup /usr/local/rustup
RUN chmod -R a+w /usr/local/rustup /usr/local/cargo

# 5. [官方镜像拼接] 精准注入 Node.js 24 LTS 环境
COPY --from=node-source /usr/local/bin/node /usr/local/bin/node
COPY --from=node-source /usr/local/include/node /usr/local/include/node
COPY --from=node-source /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
    npm install -g corepack pnpm yarn

# 6. [官方镜像拼接] 注入 Astral uv 并安装独立 Python 3.13 运行时
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/
ENV UV_PYTHON_INSTALL_DIR=/usr/local/python
RUN uv python install 3.13 && \
    PYTHON_BIN=$(uv python find 3.13) && \
    PYTHON_DIR=$(dirname "${PYTHON_BIN}") && \
    ln -sf "${PYTHON_BIN}" /usr/local/bin/python && \
    ln -sf "${PYTHON_BIN}" /usr/local/bin/python3 && \
    find /usr/local/python -name EXTERNALLY-MANAGED -delete 2>/dev/null || true && \
    uv pip install --python "${PYTHON_BIN}" --break-system-packages pip setuptools wheel ipython && \
    if [ -f "${PYTHON_DIR}/pip" ]; then ln -sf "${PYTHON_DIR}/pip" /usr/local/bin/pip; fi && \
    if [ -f "${PYTHON_DIR}/pip3" ]; then ln -sf "${PYTHON_DIR}/pip3" /usr/local/bin/pip3; fi && \
    if [ -f "${PYTHON_DIR}/ipython" ]; then ln -sf "${PYTHON_DIR}/ipython" /usr/local/bin/ipython; fi

# 7. [官方镜像拼接] 注入 OpenJDK 25 (专用于 MC MOD 编译与运行)
COPY --from=java-source /opt/java/openjdk /opt/java/openjdk

# 8. 安装 DeepSeek Harness (dsh) CLI、配置基础模版并注入自主升级工具
ENV DSH_HOME=/root/.dsh
RUN npm install -g @deepseek-ai/dsh@latest && \
    mkdir -p /root/.dsh && \
    mkdir -p /etc/dsh.template && \
    cp -r /root/.dsh/. /etc/dsh.template/

COPY update-dsh.sh /usr/local/bin/update-dsh
RUN sed -i 's/\r$//' /usr/local/bin/update-dsh && \
    chmod +x /usr/local/bin/update-dsh && \
    ln -sf /usr/local/bin/update-dsh /usr/local/bin/dsh-update

# 9. 创建工作区目录、持久化缓存目录结构及 SSH 目录
RUN mkdir -p /root/workspace \
    /cache/go/build \
    /cache/go/pkg/mod \
    /cache/cargo/registry \
    /cache/cargo/git \
    /cache/npm \
    /cache/yarn \
    /cache/pnpm \
    /cache/pip \
    /cache/uv \
    /cache/gradle \
    /var/run/sshd

# 统一配置 npm 全局缓存路径为 /cache/npm
RUN npm config set cache /cache/npm --global

# 配置交互终端默认进入 /root/workspace
RUN echo 'if [ "$PWD" = "/root" ] && [ -d "/root/workspace" ]; then cd /root/workspace; fi' >> /etc/bash.bashrc && \
    echo 'if [ "$PWD" = "/root" ] && [ -d "/root/workspace" ]; then cd /root/workspace; fi' >> /etc/zsh/zshrc 2>/dev/null || true

# 10. 导入 Entrypoint 容器入口脚本 (去除 CRLF 换行符并赋予可执行权限)
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /root/workspace

# 暴露端口: 仅暴露 SSH 服务端口 (DSH WebUI 通过 VS Code SSH 隧道自动映射)
EXPOSE 2222

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["all"]
