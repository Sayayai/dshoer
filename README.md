# dshoer

## 项目结构

```text
.
├── Dockerfile                  # 多语言环境构建文件 (Debian 12 + 官方多阶段拼接)
├── docker-compose.yml          # 一键编排启动文件
├── entrypoint.sh               # 容器初始化入口脚本 (含登录 shell 工具链自检)
├── dev-env.sh                  # 全局开发环境变量 (安装为 /etc/profile.d/30-dev-env.sh)
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


## 多语言工具链

镜像内所有语言运行时均已**开箱即用**，在 SSH / VS Code Remote 终端里直接输入命令即可：

| 语言 | 命令 | 安装位置 | 持久化缓存 (挂载于 `/cache`) |
| --- | --- | --- | --- |
| Rust | `cargo` `rustc` `rustup` | `/usr/local/cargo/bin` | `CARGO_HOME=/usr/local/cargo` → `registry`/`git` 软链到 `/cache/cargo` |
| Go | `go` (1.27) | `/usr/local/go/bin` | `GOPATH=/cache/go`、`GOMODCACHE=/cache/go/pkg/mod`、`GOCACHE=/cache/go-build` |
| Java | `java` `javac` `jar` (JDK 25) | `/opt/java/openjdk/bin` | Gradle: `GRADLE_USER_HOME=/cache/gradle` |
| Node | `node` `npm` `npx` `pnpm` | `/usr/local/bin` | `npm` → `/cache/npm`，`pnpm` → `/cache/pnpm` |
| Python | `python3` `pip` `uv` `uvx` (3.13) | `/usr/local/bin` | `PIP_CACHE_DIR=/cache/pip`、`UV_CACHE_DIR=/cache/uv` |
| 其他 | `git` `gh` `dsh` `updsh` | `/usr/local/bin` | `DSH_HOME=/root/.dsh` |

Go 常用配置（通过 `GOENV=/cache/go/env` 持久化，容器重建后依然生效）：
```bash
go version                                  # go version go1.27.x linux/amd64
go env -w GOPROXY=https://goproxy.cn,direct  # 国内加速 (可选)
go install example.com/cmd@latest            # 产物落在 /cache/go/bin (已在 PATH 中)
```

### 为什么以前 `cargo` 会 command not found？

Debian 的 `/etc/profile` 在每次登录会话开始时会把 `PATH` **强制重置**为系统默认值
（`/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`）；而 OpenSSH 的 `sshd`
在 `do_setup_env()` 中会**重建一份全新环境**，根本不继承 Docker 的 `ENV`。
于是 Dockerfile 里 `ENV PATH` 追加的 `/usr/local/cargo/bin`（cargo / rustc）、
`/opt/java/openjdk/bin`（java / javac）、`/usr/local/go/bin`（go）在
**VS Code Remote-SSH 终端**里全部丢失 → `command not found`。
（`docker exec` 反而正常，因为那条路径继承了镜像 `ENV`，这也是问题隐蔽的原因。）

现在通过 `dev-env.sh` 统一注入到 4 个位置，覆盖所有 shell 场景：

| 注入位置 | 覆盖场景 |
| --- | --- |
| `/etc/profile.d/30-dev-env.sh` | SSH 登录 / VS Code Remote 终端（登录 shell） |
| `/etc/bash.bashrc`、`/root/.bashrc` | `docker exec -it full-dev-env bash`（交互式非登录 shell） |
| `/etc/environment`（PAM `pam_env`，Debian sshd 默认加载） | `ssh host -p 52333 'go build'`（非交互 shell，PAM 环境在 sshd 设置 PATH 之后合并，优先级更高） |
| `BASH_ENV=/etc/profile.d/30-dev-env.sh` | 非交互 bash 脚本（`bash build.sh`、shebang 脚本、`bash -s`） |

脚本严格幂等：重复 source 不会让 `PATH` 膨胀，且优先级目录顺序与 Dockerfile 保持一致。
容器启动时会自动做一次登录 shell 自检，若仍有命令缺失会打印 `[WARN]` 及排查提示。

```bash
# 手工自检 (任意终端)
bash -lc 'for t in rustc cargo go java javac node pnpm python3 uv gh; do printf "%-8s %s\n" "$t" "$(command -v $t)"; done'
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
