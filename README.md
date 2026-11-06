# Curtain

个人使用的 macOS 隐私屏：人离开时拉上“幕布”，实体屏幕全黑，AI agent（如 Codex Computer Use，也适用于其他基于截图和模拟输入的 agent）在幕后继续看见并操作应用。原项目名 codex-privacy-screen。

菜单栏应用使用 gamma 清零遮挡实体屏幕，支持 Touch ID/登录密码解锁，以及拉上时拦截实体输入。它是视觉隐私工具，不是安全锁屏；正常运行保持登录会话可用，仅在心跳故障恢复时请求 macOS 系统锁屏。

## 当前状态

2026-11-06：gamma 在单显示器普通桌面与原生全屏过渡现场通过，菜单栏解锁与本地输入拦截已实现。独立心跳守护替代菜单栏默认 5 分钟限制：约 10 秒无主线程心跳时先尝试系统锁屏，再结束 Curtain 恢复显示和输入。锁屏入口依赖系统私有接口，失败仍优先恢复可操作性；实测范围与待测项见[验证记录](docs/verification.md)。早期窗口遮罩在全屏动画中闪露，保留为实验 CLI。

```bash
./scripts/build.sh
open build/Curtain.app          # 菜单栏应用（开发版）
./build/curtain-poc --gamma --duration 90   # 实验 CLI
```

支持 macOS 15 及以上（Apple 芯片；构建目标与 `Info.plist` 一致）。日常使用与验证在 macOS 26；15 与 27 尚未实测。

菜单栏应用默认不限时，解锁界面 20 秒无操作回黑；正常恢复用 Touch ID/密码，Ctrl+Cmd+Q 可进入系统锁屏。日志位于 `~/Library/Logs/Curtain/curtain.log`，含 PID；终端可用 `kill -TERM <pid>`，进程无响应时用 `kill -KILL <pid>` 恢复。故障锁屏会中断 Computer Use，详见[心跳守护](docs/subsystems/recovery-watchdog.md)。

实验 CLI 到时自动退出：持续时间 1–300 秒，默认 90 秒。`--exclude-capture` 启用 `.none` 对照；`--no-overlay` 只检查退出生命周期；`--gamma` 不用窗口，把显示器 gamma 清零，退出时自动恢复。UU 等远程画面仍显示正常内容，需要在实体屏幕前验证。

测试页面：[fixtures/click-test.html](fixtures/click-test.html)。GUI 验证使用现有 Computer Use；操作步骤、清理和证据见 [验证记录](docs/verification.md)。

## 阅读入口

- [产品需求梳理](docs/requirements.md)：菜单栏、隐私屏、密码/Touch ID 解锁、UU 冲突与分阶段。
- [需求分析与实验方案](docs/poc-plan.md)：核心假设、测试顺序与继续条件。
- [架构地图](docs/architecture.md)：模块归属和实现状态。
- [路线图](docs/roadmap.md)：先验证兼容性，再讨论锁屏体验。
- [子系统索引](docs/subsystems/README.md)：遮罩和 Computer Use 验证契约。
- [技术选择](docs/decisions/0001-native-appkit-poc.md)：为什么先做原生 AppKit 实验。

文档组织参考同级 `dify-cli` 的 agent 协作结构，具体技术约束按本项目重新定义。
