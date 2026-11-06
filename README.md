# Curtain

个人使用的 macOS 隐私屏：人离开时拉上“幕布”，实体屏幕全黑，AI agent（如 Codex Computer Use，也适用于其他基于截图和模拟输入的 agent）在幕后继续看见并操作应用。原项目名 codex-privacy-screen。

用户希望最终获得类似锁屏的体验。第一阶段只验证遮挡、截图和输入是否兼容；不调用 macOS 系统锁屏，也不实现密码、菜单栏或输入拦截。

## 当前状态

2026-11-04：最小 Swift/AppKit POC 已实现并编译。现有 Computer Use 在普通遮罩下可读取 Safari 截图并执行坐标点击，Safari 全屏与返回后也可操作。UU 远程复测确认中途闪露，桌面采样已捕获退出全屏动画中的测试网页，持续遮挡失败；四项修复对照也未通过，实验改动已回退。当前仅保留 POC 和毫秒日志，实体屏幕效果及普通 Space 切换尚未验证。

```bash
./scripts/build.sh
open build/Curtain.app          # 菜单栏应用（开发版）
./build/curtain-poc --gamma --duration 90   # 实验 CLI
```

运行期间会短暂黑屏，到时自动退出。启动日志包含 PID，可从另一终端用 `kill -TERM <pid>` 结束。持续时间范围为 1–300 秒，默认 90 秒。`--exclude-capture` 启用 `.none` 对照；`--no-overlay` 不显示窗口，只检查退出生命周期。`--gamma` 为实验模式：不用窗口，把显示器 gamma 清零，退出时自动恢复；UU 等远程画面仍显示正常内容，需要在实体屏幕前验证。

测试页面：[fixtures/click-test.html](fixtures/click-test.html)。GUI 验证使用现有 Computer Use；操作步骤、清理和证据见 [验证记录](docs/verification.md)。

## 阅读入口

- [产品需求梳理](docs/requirements.md)：菜单栏、隐私屏、密码/Touch ID 解锁、UU 冲突与分阶段。
- [需求分析与实验方案](docs/poc-plan.md)：核心假设、测试顺序与继续条件。
- [架构地图](docs/architecture.md)：模块归属和实现状态。
- [路线图](docs/roadmap.md)：先验证兼容性，再讨论锁屏体验。
- [子系统索引](docs/subsystems/README.md)：遮罩和 Computer Use 验证契约。
- [技术选择](docs/decisions/0001-native-appkit-poc.md)：为什么先做原生 AppKit 实验。

文档组织参考同级 `dify-cli` 的 agent 协作结构，具体技术约束按本项目重新定义。
