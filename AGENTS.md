# Notes for coding agents

## 开始前

1. 阅读 [架构地图](docs/architecture.md)，区分当前实现和设计。
2. 阅读 [产品需求](docs/requirements.md)、[需求与实验方案](docs/poc-plan.md)、[代码规范](docs/code-standards.md) 和 [LESSONS.md](LESSONS.md)。
3. 按 [子系统索引](docs/subsystems/README.md) 阅读相关契约，并核对实际源码。
4. 查看 [路线图](docs/roadmap.md) 和 [验证记录](docs/verification.md)，从尚未完成的实验继续。

## 当前阶段

2026-11-06 更新：菜单栏、本地输入拦截和解锁已实现；新增独立心跳守护，主线程约 10 秒无心跳时先尝试系统锁屏，再结束 Curtain 恢复显示和输入；菜单栏默认取消 300 秒上限。真实验收与待测范围以 [验证记录](docs/verification.md) 为准，恢复契约见 [心跳守护](docs/subsystems/recovery-watchdog.md)。以下为早期 POC 背景。

已实现最小 Swift/AppKit POC，并用现有 Computer Use 完成普通遮罩、Safari 原生全屏与返回后的截图和坐标点击。UU 远程分阶段复测已确认闪露，桌面采样捕获退出全屏动画中的测试网页，且遮罩进程仍在运行。持续遮挡失败；跨应用角色、NSPanel、独立面板与显示器捕获四项对照均失败，已回退。窗口轨迹确认至少进入全屏时遮罩可随旧 Space 动画移走，下一步需评估其他遮挡机制，不重复堆叠同类窗口属性。`--gamma` 显示管线清零方案 2026-11-05 现场通过：实体全黑、原生全屏进出不闪、Computer Use 截图与点击有效。下一步测 UU（含 UU 隐私屏开/关）与普通 Space。后台启动用 `scripts/start-detached.sh`，不要用会随 shell 结束的 `cmd &`。实体屏幕持续遮挡/切换闪露仍待现场观察，普通 Space A → B → A 尚未测试。详见 [验证记录](docs/verification.md)。

下一阶段目标是最小 Swift/AppKit POC。截图、坐标点击与实体遮挡的兼容性没有实测通过之前，不扩展密码、菜单栏、开机自启或输入拦截。

## 执行约定

- 所有项目文件和实验产物位于本目录，不修改原 `weiteng-java` 或参考项目 `dify-cli`。
- 使用已有 Codex Computer Use 做 GUI 验证。浏览器 DOM、AppleScript 或直接调用页面脚本不能冒充 GUI 点击通过。
- 用户说“chrome mcp”时，使用 `mcp__chrome_mcp_server` 的 Chrome DevTools MCP，不替换成 Chrome Extension 工具。
- 在显示遮罩前说明退出办法。实验 CLI 保留有限时自动关闭与终端结束进程兜底，不开机自启、不调用系统锁屏。菜单栏应用经用户 2026-11-06 授权使用独立心跳守护代替默认限时，只在故障恢复时请求系统锁屏；不安装常驻服务。
- 先使用专用、无敏感内容的 Safari 测试页面，避免改动用户正在处理的网页。
- 应用截图、桌面合成截图、辅助功能树、实体屏幕观察分别记录。截到应用不代表实体遮罩仍存在；读到辅助功能树不代表截图或坐标点击通过。
- `ignoresMouseEvents` 的点击穿透同样允许本地鼠标操作。POC 只能说明视觉隐私兼容性，不声称已经实现安全锁屏。
- 不假定 `NSWindow.sharingType = .none` 能排除所有截图。按实际 macOS、工具和采集路径做对照。
- 测试结束关闭遮罩和专用测试页面，恢复本次改变的窗口/全屏状态；不结束用户的 Safari 进程。
- 真实截图、桌面状态和运行日志放入忽略的 `artifacts/`；文档只保留必要的脱敏结论。
- 行为、状态或失败语义变化时，同一变更更新所属子系统文档、架构状态和验证记录。

## 构建与验证

构建：`./scripts/build.sh`。菜单栏应用：`open build/Curtain.app`，日志 `~/Library/Logs/Curtain/curtain.log`，默认无限时，独立心跳守护先就绪再黑屏；`python3 scripts/test-watchdog.py` 为不锁屏的进程级恢复测试。实验 CLI：`./build/curtain-poc --duration 90`；最多 300 秒。退出兜底：`kill -TERM <启动日志中的 pid>`；无响应时 `kill -KILL <pid>`。正常本地可用 Ctrl+Cmd+Q 进入系统锁屏。`--exclude-capture` 为 `.none` 对照，`--no-overlay` 只验证生命周期。`--gamma` 为 gamma 清零实验模式，UU 远程看不到遮挡效果，必须现场或用手机录屏验证。工具链与实际结果见 [验证记录](docs/verification.md)。

验证以 [实验方案](docs/poc-plan.md) 为准。编译成功、模拟测试和真实 GUI 验收分别报告，不把计划写成结果。原生窗口与 Space 行为必须实测，不用复述属性值的单元测试替代。

## 评审

沿“启动 → 窗口覆盖 → 实体显示 → Computer Use 截图 → 输入 → Space/全屏切换 → 自动退出与清理”检查完整链路。

- Write all future commit messages and project comments/notes in English.
- Use `Area: user-visible behavior change` for commit messages, and state what passed validation and what remains unverified in the commit body when applicable.
