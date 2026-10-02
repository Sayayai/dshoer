#!/bin/bash
set -e

# ==============================================================================
# DeepSeek Harness (dsh) 容器内升级脚本
# 用法:
#   updsh              # 升级至最新稳定版本 (latest)
#   updsh next         # 升级至最新预览版本 (next)
#   updsh 0.1.7-rc.2   # 升级至指定版本
# ==============================================================================

TARGET_VERSION="${1:-latest}"

echo "=================================================================="
echo "  [DSH] 开始更新 DeepSeek Harness (目标版本: ${TARGET_VERSION})"
echo "=================================================================="

# 1. 停止当前运行的 dsh web 服务 (释放 3080 端口)
echo "[DSH] 1/4: 停止后台 DSH Web 服务..."
DSH_PIDS=$(pgrep -f "dsh web" 2>/dev/null || true)
if [ -n "${DSH_PIDS}" ]; then
    kill -15 ${DSH_PIDS} 2>/dev/null || true
    sleep 2
    kill -9 $(pgrep -f "dsh web" 2>/dev/null || true) 2>/dev/null || true
fi

# 2. 全局安装/更新 dsh
echo "[DSH] 2/4: 执行 npm install -g @deepseek-ai/dsh@${TARGET_VERSION}..."
npm install -g "@deepseek-ai/dsh@${TARGET_VERSION}"

# 3. 校验新版本
echo "[DSH] 3/4: 校验版本..."
NEW_VERSION=$(dsh --version 2>/dev/null || echo "Unknown")

# 4. 重启 DSH Web 服务并清空旧日志
echo "[DSH] 4/4: 重启 DSH WebUI (端口 3080)..."
> /tmp/dsh-web.log 2>/dev/null || true
nohup dsh web --host 127.0.0.1 --port 3080 --no-open >> /tmp/dsh-web.log 2>&1 &
NEW_PID=$!
echo ${NEW_PID} > /var/run/dsh-web.pid

# 5. 等待并提取带 Token 的完整认证访问链接
TOKEN_URL=""
for i in $(seq 1 20); do
    if [ -f /tmp/dsh-web.log ]; then
        CLEAN_LOG=$(sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' /tmp/dsh-web.log 2>/dev/null || cat /tmp/dsh-web.log || true)
        TOKEN_URL=$(echo "${CLEAN_LOG}" | grep -Eo 'https?://[a-zA-Z0-9.:_-]+/\?token=[a-zA-Z0-9._~%-]+' | tail -n 1 || true)
        if [ -z "${TOKEN_URL}" ]; then
            TOKEN_URL=$(echo "${CLEAN_LOG}" | grep -Eo 'https?://[^[:space:]"'\''`]*token=[^[:space:]"'\''`]*' | tail -n 1 || true)
        fi
        if [ -n "${TOKEN_URL}" ]; then
            break
        fi
    fi
    sleep 0.5
done

echo "=================================================================="
echo "  [DSH] 更新完成！"
echo "  - 当前版本: ${NEW_VERSION}"
echo "  - 服务 PID: ${NEW_PID}"
if [ -n "${TOKEN_URL}" ]; then
    echo "  - 认证链接: ${TOKEN_URL}"
    echo "  - 提示: 复制上方完整链接在浏览器中打开即可免密登录 WebUI"
else
    echo "  - 访问地址: http://127.0.0.1:3080"
    echo "  - 提示: 未能在 10s 内捕获到 Token，请执行 cat /tmp/dsh-web.log 查看完整输出"
fi
echo "  - 查看日志: tail -f /tmp/dsh-web.log"
echo "=================================================================="
