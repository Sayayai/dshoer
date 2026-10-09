#!/bin/bash
set -e

# ==============================================================================
# Entrypoint Script for Remote SSH Dev Environment
# ==============================================================================

# 1. 初始化工作区及各语言缓存目录结构
mkdir -p /root/workspace \
         /cache/cargo/registry \
         /cache/cargo/git \
         /cache/npm \
         /cache/pnpm \
         /cache/pip \
         /cache/uv \
         /cache/gradle \
         /cache/go/bin \
         /cache/go/pkg/mod \
         /cache/go-build

# 1.1 兜底修复: 确保全局环境变量注入文件就绪
#     (老版本镜像升级上来时 /etc/profile.d/30-dev-env.sh 可能缺失, 会导致
#      SSH 登录会话中 cargo / java / go 等命令 command not found)
if [ ! -r /etc/profile.d/30-dev-env.sh ]; then
    echo "[Entrypoint] [WARN] /etc/profile.d/30-dev-env.sh missing, recreating minimal fallback..."
    cat << 'EOF' > /etc/profile.d/30-dev-env.sh
# 兜底注入 (幂等, 完整版本见仓库 dev-env.sh)
if [ -z "${DEV_ENV_LOADED:-}" ]; then
    DEV_ENV_LOADED=1; export DEV_ENV_LOADED
    JAVA_HOME=/opt/java/openjdk;   export JAVA_HOME
    GOROOT=/usr/local/go;          export GOROOT
    GOPATH=/cache/go;              export GOPATH
    GOMODCACHE=/cache/go/pkg/mod;  export GOMODCACHE
    GOCACHE=/cache/go-build;       export GOCACHE
    CARGO_HOME=/usr/local/cargo;   export CARGO_HOME
    RUSTUP_HOME=/usr/local/rustup; export RUSTUP_HOME
    PATH="/root/workspace/.bin:${GOPATH}/bin:${GOROOT}/bin:${JAVA_HOME}/bin:${CARGO_HOME}/bin:${PATH}"
    export PATH
fi
EOF
    chmod 0644 /etc/profile.d/30-dev-env.sh
fi
if ! grep -qF '/etc/profile.d/30-dev-env.sh' /etc/bash.bashrc 2>/dev/null; then
    echo '[ -r /etc/profile.d/30-dev-env.sh ] && . /etc/profile.d/30-dev-env.sh' >> /etc/bash.bashrc
fi
if ! grep -qF '/etc/profile.d/30-dev-env.sh' /root/.bashrc 2>/dev/null; then
    echo '[ -r /etc/profile.d/30-dev-env.sh ] && . /etc/profile.d/30-dev-env.sh' >> /root/.bashrc
fi

# 2. 映射 Cargo 与 Gradle 缓存至持久化 /cache 目录 (MC MOD 构建利器)
if [ ! -L /usr/local/cargo/registry ]; then
    rm -rf /usr/local/cargo/registry
    ln -s /cache/cargo/registry /usr/local/cargo/registry
fi
if [ ! -L /usr/local/cargo/git ]; then
    rm -rf /usr/local/cargo/git
    ln -s /cache/cargo/git /usr/local/cargo/git
fi
if [ ! -L /root/.gradle ]; then
    mkdir -p /cache/gradle
    ln -s /cache/gradle /root/.gradle 2>/dev/null || true
fi

# 3. 确保 DSH 配置与应用数据持久化目录就绪，并在首次启动时同步模版
mkdir -p /root/.dsh
if [ ! -d "/root/.dsh/profiles/web" ] || [ -z "$(ls -A /root/.dsh)" ]; then
    echo "[Entrypoint] Initializing DSH configuration into /root/.dsh..."
    cp -r /etc/dsh.template/. /root/.dsh/ 2>/dev/null || true
fi

# 4. 自动配置 Git 身份信息 (支持免手动重复配置)
if [ -n "${GIT_USER_NAME}" ]; then
    git config --global user.name "${GIT_USER_NAME}"
fi
if [ -n "${GIT_USER_EMAIL}" ]; then
    git config --global user.email "${GIT_USER_EMAIL}"
fi

# 5. 配置 OpenSSH 服务 (供本地 VS Code Remote-SSH 直连)
mkdir -p /var/run/sshd /root/.ssh /cache/ssh
chmod 700 /root/.ssh

# 配置 SSH Host Keys 持久化 (防止容器重建后指纹变化导致 known_hosts 冲突)
if [ ! -f /cache/ssh/ssh_host_ed25519_key ]; then
    ssh-keygen -A
    cp -a /etc/ssh/ssh_host_* /cache/ssh/ 2>/dev/null || true
else
    cp -a /cache/ssh/ssh_host_* /etc/ssh/ 2>/dev/null || true
fi
chmod 600 /etc/ssh/ssh_host_*_key 2>/dev/null || true

# 注入公钥并彻底关闭密码认证 (强制纯密钥安全模式)
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

if [ -n "${SSH_PUBLIC_KEY}" ]; then
    # 自动去除首尾可能由 docker-compose 或 .env 传入的多余引号 (双引号或单引号)
    CLEAN_KEY=$(echo "${SSH_PUBLIC_KEY}" | sed -e 's/^["'"'"']//' -e 's/["'"'"']$//')
    if [ -n "${CLEAN_KEY}" ] && ! grep -qF "${CLEAN_KEY}" /root/.ssh/authorized_keys 2>/dev/null; then
        echo "${CLEAN_KEY}" >> /root/.ssh/authorized_keys
    fi
    echo "[Entrypoint] SSH public key verified for root login."
else
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "  [WARNING] SSH_PUBLIC_KEY is not set in .env!"
    echo "  Password authentication is DISABLED. You will not be able to connect"
    echo "  via SSH until you set SSH_PUBLIC_KEY in .env and restart."
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
fi

# 锁定 root 密码 (彻底清除/锁定本地密码，不可用密码登入)
passwd -l root 2>/dev/null || true

# 配置 OpenSSH 安全策略: 端口 2222，仅允许 root 密钥登录，彻底禁用密码与键盘交互认证
mkdir -p /etc/ssh/sshd_config.d
cat << 'EOF' > /etc/ssh/sshd_config.d/99-key-only.conf
Port 2222
PermitRootLogin prohibit-password
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
EOF

sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config 2>/dev/null || true
sed -i 's/.*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config 2>/dev/null || true
sed -i 's/.*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config 2>/dev/null || true
sed -i 's/.*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config 2>/dev/null || true
sed -i 's/.*KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' /etc/ssh/sshd_config 2>/dev/null || true

echo "=================================================================="
echo "       Remote SSH Dev Environment is Ready!                       "
echo "=================================================================="
echo "  - Rust Version:    $(rustc --version 2>/dev/null || echo 'Not found')"
echo "  - Go Version:      $(go version 2>/dev/null || echo 'Not found')"
echo "  - Java Version:    $(java -version 2>&1 | head -n 1 || echo 'Not found')"
echo "  - Node Version:    $(node -v 2>/dev/null || echo 'Not found')"
echo "  - Python Version:  $(python3 --version 2>/dev/null || echo 'Not found')"
echo "  - DSH Version:     $(dsh --version 2>/dev/null || echo 'Installed')"
echo "  - GitHub CLI:      $(gh --version 2>/dev/null | head -n 1 || echo 'Installed')"
echo "  - Git User:        $(git config --global user.name 2>/dev/null || echo 'Not configured')"
echo "  - SSH Port:        2222 (for local desktop VS Code Remote-SSH)"
echo "  - DSH Web:         3080 (http://localhost:3080)"
echo "  - DSH Config/Data: /root/.dsh (host: ./fun/dsh)"
echo "  - Workspace:       /root/workspace (host: ./workspace)"
echo "  - Cache Root:      /cache (cargo / go / gradle / npm / pip / uv)"
echo "=================================================================="

# 5.1 环境自检: 模拟 SSH 登录 shell (/etc/profile + profile.d) 校验各语言工具
#     这是 "cargo / java / go 直接输入却 command not found" 问题的回归防线
MISSING_TOOLS=""
for TOOL in rustc cargo go java javac node npm pnpm python3 pip uv gh git dsh; do
    if ! bash -lc "command -v ${TOOL}" >/dev/null 2>&1; then
        MISSING_TOOLS="${MISSING_TOOLS} ${TOOL}"
    fi
done
if [ -n "${MISSING_TOOLS}" ]; then
    echo "  [WARN] Login shell 中仍无法直接调用:${MISSING_TOOLS}"
    echo "         排查: bash -lc 'echo \$PATH'; cat /etc/profile.d/30-dev-env.sh"
else
    echo "  [OK] 登录 shell 自检通过: 所有语言工具均可直接调用 (cargo / go / java / node ...)"
fi
echo "=================================================================="

# 6. 执行控制
case "$1" in
    "all")
        echo "[Entrypoint] Starting SSH Daemon on port 2222..."
        /usr/sbin/sshd

        echo "[Entrypoint] Starting DeepSeek Harness (dsh web) on port 3080..."
        nohup dsh web --host 127.0.0.1 --port 3080 --no-open >> /tmp/dsh-web.log 2>&1 &
        echo $! > /var/run/dsh-web.pid

        echo "[Entrypoint] All background services started."
        echo "  -> Ready for VS Code Remote-SSH connect: ssh root@<host> -p 2222"
        echo "  -> To update DSH in-container, simply run: updsh"
        echo "  -> To login GitHub, run: gh auth login"
        echo "  -> DSH Web log streaming:"

        trap 'echo "Stopping services..."; kill $(cat /var/run/dsh-web.pid 2>/dev/null) 2>/dev/null || true; exit 0' SIGTERM SIGINT
        tail -F /tmp/dsh-web.log
        ;;

    "ssh")
        echo "[Entrypoint] Starting SSH Daemon only on port 2222..."
        exec /usr/sbin/sshd -D
        ;;

    "dsh")
        echo "[Entrypoint] Starting DeepSeek Harness only on port 3080..."
        exec dsh web --host 127.0.0.1 --port 3080 --no-open
        ;;

    *)
        exec "$@"
        ;;
esac
