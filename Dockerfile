# ==============================================================================
# 全功能多语言远端开发环境 Dockerfile (Debian 12 Bookworm)
# 架构: 官方镜像精细拼接 + 极简 SSH 远端开发 (无冗余 Web VSCode)
# 针对 GitHub Actions 多架构 (linux/amd64, linux/arm64) 云编译极速优化
# ==============================================================================

# 阶段 1: 提取官方 Rust 工具链 (rustup, rustc, cargo) 并剥离文档、预先赋予写权限 (避免下阶段层冗余复制)
FROM rust:bookworm AS rust-source
RUN rm -rf /usr/local/rustup/toolchains/*/share/doc \
           /usr/local/rustup/toolchains/*/share/man && \
    chmod -R a+w /usr/local/rustup /usr/local/cargo

# 阶段 2: 提取官方 Node.js 24 LTS
FROM node:24-bookworm-slim AS node-source

# 阶段 3: 提取官方 Eclipse Temurin OpenJDK 25 并剔除源码包、文档与 jmods 模块库 (~350MB+)
FROM eclipse-temurin:25-jdk AS java-source
RUN rm -rf /opt/java/openjdk/lib/src.zip \
           /opt/java/openjdk/demo \
           /opt/java/openjdk/man \
           /opt/java/openjdk/jmods

# 阶段 4: 提取官方 Go 1.27 工具链 (剔除文档、示例与标准库测试用例, GOPATH 走 /cache 持久化)
FROM golang:1.27-bookworm AS go-source
RUN rm -rf /usr/local/go/doc \
           /usr/local/go/test \
           /usr/local/go/api \
           /usr/local/go/blog && \
    find /usr/local/go -name "*_test.go" -delete 2>/dev/null || true

# ------------------------------------------------------------------------------
# 主阶段: 最终运行镜像
# ------------------------------------------------------------------------------
FROM debian:bookworm-slim

LABEL maintainer="developer"
LABEL description="Lean Multi-arch Remote Dev Container with Rust, Go 1.27, Node, Python, Java 25, SSH, and DeepSeek Harness"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# 1. 基础系统与开发工具链 (包含 OpenSSH-Server, GitHub CLI 以及 MC 无头图形底库)
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    git \
    git-lfs \
    gh \
    build-essential \
    pkg-config \
    libssl-dev \
    jq \
    procps \
    unzip \
    tar \
    xz-utils \
    openssh-server \
    openssh-client \
    xvfb \
    libgl1-mesa-dri \
    libgl1 \
    libglfw3 \
    libopenal1 \
    libasound2 \
    libxcursor1 \
    libxrandr2 \
    libxinerama1 \
    libxi6 \
    libxext6 \
    fontconfig \
    fonts-dejavu-core \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 2. 统一全局环境变量与多语言缓存路径
ENV WORKSPACE=/root/workspace \
    CACHE_DIR=/cache \
    JAVA_HOME=/opt/java/openjdk \
    GOROOT=/usr/local/go \
    GOPATH=/cache/go \
    GOMODCACHE=/cache/go/pkg/mod \
    GOCACHE=/cache/go-build \
    GOENV=/cache/go/env \
    GRADLE_USER_HOME=/cache/gradle \
    RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PIP_CACHE_DIR=/cache/pip \
    UV_CACHE_DIR=/cache/uv \
    PNPM_HOME=/cache/pnpm \
    DSH_HOME=/root/.dsh \
    BASH_ENV=/etc/profile.d/30-dev-env.sh

ENV PATH=/root/workspace/.bin:$JAVA_HOME/bin:$GOROOT/bin:$GOPATH/bin:/usr/local/cargo/bin:/cache/cargo/bin:/usr/local/bin:/usr/bin:/bin:$PATH

# 3. [官方镜像拼接] 注入 Rust 运行时 (rustc, cargo, rustup)
# 注: 权限已在阶段 1 完成赋权，直接 COPY 继承权限，彻底消除 OverlayFS 层的全量冗余复制 (~1.2GB+)
COPY --from=rust-source /usr/local/cargo /usr/local/cargo
COPY --from=rust-source /usr/local/rustup /usr/local/rustup

# 4. [官方镜像拼接] 精准注入 Node.js 24 LTS 环境，合并全局安装并清理缓存
COPY --from=node-source /usr/local/bin/node /usr/local/bin/node
COPY --from=node-source /usr/local/include/node /usr/local/include/node
COPY --from=node-source /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
    npm install -g pnpm @deepseek-ai/dsh@latest && \
    npm cache clean --force && \
    rm -rf /root/.npm

# 5. [官方镜像拼接] 注入 Astral uv 并安装独立 Python 3.13 运行时 (精简内置测试用例)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/
ENV UV_PYTHON_INSTALL_DIR=/usr/local/python
RUN uv python install 3.13 && \
    PYTHON_BIN=$(uv python find 3.13) && \
    PYTHON_DIR=$(dirname "${PYTHON_BIN}") && \
    ln -sf "${PYTHON_BIN}" /usr/local/bin/python && \
    ln -sf "${PYTHON_BIN}" /usr/local/bin/python3 && \
    find /usr/local/python -name EXTERNALLY-MANAGED -delete 2>/dev/null || true && \
    uv pip install --python "${PYTHON_BIN}" --break-system-packages pip && \
    if [ -f "${PYTHON_DIR}/pip" ]; then ln -sf "${PYTHON_DIR}/pip" /usr/local/bin/pip; fi && \
    if [ -f "${PYTHON_DIR}/pip3" ]; then ln -sf "${PYTHON_DIR}/pip3" /usr/local/bin/pip3; fi && \
    find /usr/local/python -type d -name "test" -o -type d -name "tests" 2>/dev/null | xargs rm -rf 2>/dev/null || true && \
    find /usr/local/python -name "*.pyc" -delete 2>/dev/null || true && \
    uv cache clean && \
    rm -rf /root/.cache

# 6. [官方镜像拼接] 注入 OpenJDK 25 (专用于 MC MOD 编译与运行)
COPY --from=java-source /opt/java/openjdk /opt/java/openjdk

# 7. [官方镜像拼接] 注入 Go 1.27 工具链 (GOROOT=/usr/local/go, 编译产物缓存走 /cache)
COPY --from=go-source /usr/local/go /usr/local/go

# 8. 配置 DeepSeek Harness (dsh) 模版并注入自主升级工具
RUN mkdir -p /root/.dsh && \
    mkdir -p /etc/dsh.template && \
    cp -r /root/.dsh/. /etc/dsh.template/

COPY updsh.sh /usr/local/bin/updsh
RUN sed -i 's/\r$//' /usr/local/bin/updsh && \
    chmod +x /usr/local/bin/updsh && \
    ln -sf /usr/local/bin/updsh /usr/local/bin/update-dsh

# 9. 创建工作区目录、持久化缓存目录结构 (含 Go 缓存) 及 SSH 目录
RUN mkdir -p /root/workspace \
    /cache/cargo/registry \
    /cache/cargo/git \
    /cache/npm \
    /cache/pnpm \
    /cache/pip \
    /cache/uv \
    /cache/gradle \
    /cache/go \
    /cache/go/bin \
    /cache/go/pkg/mod \
    /cache/go-build \
    /var/run/sshd && \
    npm config set cache /cache/npm --global && \
    echo 'if [ "$PWD" = "/root" ] && [ -d "/root/workspace" ]; then cd /root/workspace; fi' >> /etc/bash.bashrc

# 10. 修复 SSH / VS Code Remote 终端中 "command not found" 问题
#     根因 (已对照 Debian /etc/profile 与 OpenSSH session.c 源码确认):
#       a) sshd 的 do_setup_env() 会重建一份全新环境, 完全不继承 Docker ENV;
#       b) Debian 的 /etc/profile 又会在登录会话里把 PATH 强制重置为系统默认值。
#       于是 ENV PATH 里追加的 /usr/local/cargo/bin (cargo/rustc)、
#       /opt/java/openjdk/bin (java/javac)、/usr/local/go/bin (go) 全部丢失。
#     修复: 通过 shell/PAM 启动文件重新注入, 覆盖全部会话类型
#       - 登录 shell:        /etc/profile.d/30-dev-env.sh
#       - 交互非登录 shell:  /etc/bash.bashrc、/root/.bashrc
#       - 非交互 shell:      /etc/environment (Debian sshd 默认 pam_env.so,
#                           且 PAM env 在 sshd 设置 PATH 之后合并, 优先级更高)
#       - 非交互 bash 脚本:  BASH_ENV
COPY dev-env.sh /etc/profile.d/30-dev-env.sh

RUN sed -i 's/\r$//' /etc/profile.d/30-dev-env.sh && \
    chmod 0644 /etc/profile.d/30-dev-env.sh && \
    touch /etc/bash.bashrc /root/.bashrc && \
    SOURCE_LINE='[ -r /etc/profile.d/30-dev-env.sh ] && . /etc/profile.d/30-dev-env.sh' && \
    { grep -qF '/etc/profile.d/30-dev-env.sh' /etc/bash.bashrc || echo "${SOURCE_LINE}" >> /etc/bash.bashrc; } && \
    { grep -qF '/etc/profile.d/30-dev-env.sh' /root/.bashrc || echo "${SOURCE_LINE}" >> /root/.bashrc; } && \
    printf '%s\n' \
      'JAVA_HOME=/opt/java/openjdk' \
      'GOROOT=/usr/local/go' \
      'GOPATH=/cache/go' \
      'CARGO_HOME=/usr/local/cargo' \
      'RUSTUP_HOME=/usr/local/rustup' \
      'GRADLE_USER_HOME=/cache/gradle' \
      'GOMODCACHE=/cache/go/pkg/mod' \
      'GOCACHE=/cache/go-build' \
      'GOENV=/cache/go/env' \
      'PIP_CACHE_DIR=/cache/pip' \
      'UV_CACHE_DIR=/cache/uv' \
      'PNPM_HOME=/cache/pnpm' \
      'DSH_HOME=/root/.dsh' \
      'BASH_ENV=/etc/profile.d/30-dev-env.sh' \
      'PATH=/root/workspace/.bin:/cache/go/bin:/usr/local/go/bin:/opt/java/openjdk/bin:/usr/local/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
      > /etc/environment

# 11. 导入 Entrypoint 容器入口脚本 (去除 CRLF 换行符并赋予可执行权限)
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /root/workspace

# 暴露端口: 仅暴露 SSH 服务端口 (DSH WebUI 通过 VS Code SSH 隧道自动映射)
EXPOSE 2222

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["all"]
