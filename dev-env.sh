#!/bin/sh
# ==============================================================================
# 全局多语言开发环境变量统一定义 (安装为 /etc/profile.d/30-dev-env.sh)
# ------------------------------------------------------------------------------
# 背景 (为什么需要这个文件):
#   1) OpenSSH 的 sshd 在 do_setup_env() 里会重建一份全新环境, 完全不继承 Docker ENV;
#   2) Debian 的 /etc/profile 在会话开始时又会把 PATH 强制重置为
#      "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"。
#   于是 Dockerfile 里 ENV PATH 设置的 /usr/local/cargo/bin、/opt/java/openjdk/bin、
#   /usr/local/go/bin 等目录在 SSH 登录会话 (VS Code Remote-SSH 终端) 中全部丢失,
#   直接导致 cargo / rustc / rustup / java / javac / go 等命令 "command not found"。
#
# 解决方案 (四处联动, 覆盖所有会话类型):
#   1) /etc/profile.d/30-dev-env.sh  -> 登录 shell (SSH 登录 / VS Code Remote 终端)
#   2) /etc/bash.bashrc + /root/.bashrc -> 交互式非登录 shell (docker exec -it bash)
#   3) /etc/environment (PAM pam_env, Debian sshd 默认启用) -> 非交互 shell
#      (如 ssh host -p 52233 'cargo build') 及所有走 PAM 的会话
#   4) BASH_ENV=/etc/profile.d/30-dev-env.sh -> 非交互 bash 脚本
#      (bash build.sh / shebang 脚本 / bash -s); 注: bash -c 不读 BASH_ENV
#
# 本脚本必须保持 POSIX sh 兼容 (dash 登录时也会 source), 且严格幂等。
# ==============================================================================

# 标记位 (仅用于排查问题: env | grep DEV_ENV)
DEV_ENV_LOADED=1
export DEV_ENV_LOADED

# ------------------------------------------------------------------------------
# 1. 各语言运行时根目录 (工具链安装位置, 与 Dockerfile 完全一致)
# ------------------------------------------------------------------------------
JAVA_HOME=/opt/java/openjdk;              export JAVA_HOME
GOROOT=/usr/local/go;                     export GOROOT
GOPATH=/cache/go;                         export GOPATH
CARGO_HOME=/usr/local/cargo;              export CARGO_HOME
RUSTUP_HOME=/usr/local/rustup;            export RUSTUP_HOME

# ------------------------------------------------------------------------------
# 2. 持久化缓存目录 (全部挂载到 /cache, 容器重建后依赖不丢)
# ------------------------------------------------------------------------------
GRADLE_USER_HOME=/cache/gradle;           export GRADLE_USER_HOME
GOMODCACHE=/cache/go/pkg/mod;             export GOMODCACHE
GOCACHE=/cache/go-build;                  export GOCACHE
GOENV=/cache/go/env;                      export GOENV
PIP_CACHE_DIR=/cache/pip;                 export PIP_CACHE_DIR
UV_CACHE_DIR=/cache/uv;                   export UV_CACHE_DIR
PNPM_HOME=/cache/pnpm;                    export PNPM_HOME
DSH_HOME=/root/.dsh;                      export DSH_HOME

# ------------------------------------------------------------------------------
# 3. 统一 PATH: 把各语言 bin 目录显式置顶 (与 Dockerfile 中 ENV PATH 顺序完全一致)
#    算法: 优先级目录段在前 + 继承原有 PATH 的其余条目 (去重)
#    幂等: 若 PATH 已是注入后的形态 (以优先级段开头) 则直接跳过, 不会重复膨胀
# ------------------------------------------------------------------------------
DEV_PRIORITY_PATH="/root/workspace/.bin:${GOPATH}/bin:${GOROOT}/bin:${JAVA_HOME}/bin:${CARGO_HOME}/bin:/usr/local/bin"

case "${PATH}" in
    "${DEV_PRIORITY_PATH}" | "${DEV_PRIORITY_PATH}":*)
        : ;;                                        # 已注入, 无需处理
    *)
        NEW_PATH="${DEV_PRIORITY_PATH}"
        OLD_IFS="${IFS}"
        IFS=:
        for DIR in ${PATH}; do
            [ -n "${DIR}" ] || continue
            case ":${NEW_PATH}:" in
                *":${DIR}:"*) ;;                     # 已由优先级段提供, 跳过
                *) NEW_PATH="${NEW_PATH}:${DIR}" ;;  # 其余条目按原顺序追加在后
            esac
        done
        IFS="${OLD_IFS}"
        PATH="${NEW_PATH}"
        unset NEW_PATH DIR OLD_IFS
        ;;
esac

export PATH
unset DEV_PRIORITY_PATH
