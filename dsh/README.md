# DeepSeek Harness (dsh) 配置与应用数据目录

本目录通过 Docker 挂载至容器内部的 `/root/.dsh`。

### 作用说明
1. **配置独立持久化**：DeepSeek Harness 的所有运行配置（如 `settings.yaml`、模型列表、API Key、环境配置）、预装的两款官方实验团队插件（`@deepseek-ai/dsh-experimental-agent-team-profile` 与 `@deepseek-ai/dsh-experimental-agent-team-web-profile`）及本地智能体会话数据均保存在此目录中。首次启动容器时会自动完成插件模版初始化。
2. **便捷修改**：您可以在宿主机直接使用喜欢的编辑器打开并修改本目录下的配置文件，无需通过 `docker exec` 进入容器内部操作。
3. **安全防护**：本目录已在 `.gitignore` 中配置忽略规则，避免本地填写的 API Key、登录 Token 及历史会话意外提交到公共 GitHub 仓库。
