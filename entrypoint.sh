#!/bin/bash
set -e

# ==============================================================================
# Entrypoint Script for Remote SSH Dev Environment
# ==============================================================================

# 1. 初始化各语言缓存目录结构
mkdir -p /cache/go/build \
         /cache/go/pkg/mod \
         /cache/cargo/registry \
         /cache/cargo/git \
         /cache/npm \
         /cache/yarn \
         /cache/pnpm \
         /cache/pip \
         /cache/uv

# 2. 映射 Cargo 缓存至持久化 /cache 目录
if [ ! -L /usr/local/cargo/registry ]; then
    rm -rf /usr/local/cargo/registry
    ln -s /cache/cargo/registry /usr/local/cargo/registry
fi
if [ ! -L /usr/local/cargo/git ]; then
    rm -rf /usr/local/cargo/git
    ln -s /cache/cargo/git /usr/local/cargo/git
fi

# 3. 确保 DSH 配置与应用数据持久化目录就绪，并在首次启动时同步预置实验插件与配置模版
mkdir -p /root/.dsh
if [ ! -d "/root/.dsh/profiles/web" ] || [ -z "$(ls -A /root/.dsh)" ]; then
    echo "[Entrypoint] Initializing DSH configuration and pre-installed experimental plugins into /root/.dsh..."
    cp -r /etc/dsh.template/. /root/.dsh/ 2>/dev/null || true
fi

# 4. 配置 OpenSSH 服务 (供本地 VS Code Remote-SSH 直连)
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
    if ! grep -qF "${SSH_PUBLIC_KEY}" /root/.ssh/authorized_keys 2>/dev/null; then
        echo "${SSH_PUBLIC_KEY}" >> /root/.ssh/authorized_keys
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
echo "  - Go Version:      $(go version 2>/dev/null || echo 'Not found')"
echo "  - Rust Version:    $(rustc --version 2>/dev/null || echo 'Not found')"
echo "  - Node Version:    $(node -v 2>/dev/null || echo 'Not found')"
echo "  - Python Version:  $(python3 --version 2>/dev/null || echo 'Not found')"
echo "  - DSH Version:     $(dsh --version 2>/dev/null || echo 'Installed')"
echo "  - SSH Port:        2222 (for local desktop VS Code Remote-SSH)"
echo "  - DSH Web:         3080 (http://localhost:3080)"
echo "  - DSH Config/Data: /root/.dsh (host: ./dsh)"
echo "  - Workspace:       /workspace (host: ./workspace)"
echo "  - Cache Root:      /cache"
echo "=================================================================="

# 5. 执行控制
case "$1" in
    "all")
        echo "[Entrypoint] Starting SSH Daemon on port 2222..."
        /usr/sbin/sshd

        # 确保 VS Code Server 的 cli server 软链就绪
        for d in /root/.vscode-server/bin/*; do
            if [ -d "$d" ]; then
                c=$(basename "$d")
                mkdir -p "/root/.vscode-server/cli/servers/Stable-${c}"
                ln -sf "$d" "/root/.vscode-server/cli/servers/Stable-${c}/server"
            fi
        done

        echo "[Entrypoint] Starting DeepSeek Harness (dsh web) on port 3080..."
        dsh web --no-open > /tmp/dsh-web.log 2>&1 &
        DSH_PID=$!

        echo "[Entrypoint] All background services started."
        echo "  -> Ready for VS Code Remote-SSH connect: ssh root@<host> -p 2222"
        echo "  -> DSH Web log streaming:"

        trap 'echo "Stopping services..."; kill ${DSH_PID} 2>/dev/null || true; exit 0' SIGTERM SIGINT
        tail -F /tmp/dsh-web.log
        ;;

    "ssh")
        echo "[Entrypoint] Starting SSH Daemon only on port 2222..."
        exec /usr/sbin/sshd -D
        ;;

    "dsh")
        echo "[Entrypoint] Starting DeepSeek Harness only..."
        exec dsh web --no-open
        ;;

    *)
        exec "$@"
        ;;
esac
