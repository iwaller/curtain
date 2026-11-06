# Curtain

[English](README.md) | 简体中文

一个 macOS 菜单栏隐私屏工具：拉上幕布，实体屏幕全黑，AI agent 在幕后继续工作。

Curtain 保持当前桌面会话可用，让 Codex Computer Use 等工具继续截图和操作应用。它通过显示器 gamma 控制实现黑屏，而不是覆盖一层黑色窗口。

> **实验性项目，请自行评估使用风险。** Curtain 可能存在 bug，不保证隐私或安全。画面可能意外露出，本地输入也可能传入应用。保护敏感内容或防止未经授权的操作时，请使用 macOS 系统锁屏。

## 功能

- 遮挡实体屏幕，兼容的截图工具仍能看到桌面。
- 使用 Touch ID 或 macOS 登录密码恢复显示。
- 拉幕时拦截实体键盘和鼠标输入，需要辅助功能权限。
- 拉幕期间阻止显示器空闲睡眠。
- 独立守护进程在应用无响应时执行恢复。

## 构建与运行

需要 Apple 芯片 Mac、macOS 15 或更高版本，以及已选定命令行工具的 Xcode。已在 macOS 26 上测试，其他版本尚未验证。

支持英文和简体中文，跟随 macOS 语言偏好。也可在 **系统设置 → 通用 → 语言与地区 → 应用程序** 中单独设置 Curtain 的语言，其他语言默认使用英文。

```bash
./scripts/build.sh
open build/Curtain.app
```

构建优先使用可用的 Apple Development 签名证书，没有时使用 ad-hoc 签名。不需要第三方库。

## 使用

1. 打开 Curtain，按引导授予辅助功能权限以启用本地输入拦截。未授权时仅遮挡画面。
2. 点击菜单栏中的 **开启隐私屏**。
3. 移动鼠标或按键唤出解锁界面，使用 Touch ID 或登录密码解锁。远程使用时，从菜单选择 **解锁…**。

幕布保持拉上，直到解锁或被系统事件等中断。解锁界面 20 秒无操作后自动回黑。密码仅在本机验证，不会保存。

## 使用边界与恢复

**Curtain 用于视觉隐私，不能代替 macOS 系统锁屏。** 远程截图仍可能看到桌面。需要系统锁屏时，请按 **Control–Command–Q**。

已测试单屏原生全屏过渡，以及镜像双屏下的 Space 切换。扩展桌面、HDR、热插拔、整夜运行，以及开启输入拦截后的完整 agent／远程操作兼容性仍待验证，详见[验证记录](docs/verification.md)。

应用无响应时，守护进程会先尝试系统锁屏，再结束 Curtain，恢复显示和输入。锁屏可能失败，此时优先恢复可操作性。兜底可从 `~/Library/Logs/Curtain/curtain.log` 获取 PID，执行 `kill -TERM <pid>`；无响应时使用 `kill -KILL <pid>`。结束 Curtain 会恢复画面，除非 macOS 已锁屏。

## 开发

- [架构地图](docs/architecture.md)
- [子系统索引](docs/subsystems/README.md)
- [实验方案](docs/poc-plan.md)

实验 CLI 支持 1–300 秒的限时运行，退出后恢复显示：

```bash
./build/curtain-poc --gamma --duration 90
```

## 致谢

本项目的 `LESSONS.md`、`AGENTS.md` 和 `docs/` 目录中的文档组织方式与协作实践借鉴了 [yetone](https://github.com/yetone) 的 [Magpie](https://github.com/yetone/magpie) 项目。Magpie 使用 [MIT 协议](https://github.com/yetone/magpie/blob/main/LICENSE)。

权限引导交互（包括浮动拖动条及其飞入动画）经由 Barlet 借鉴了 [zats](https://github.com/zats) 的 [Permiso](https://github.com/zats/permiso) 项目。
