# Curtain

[English](README.md) | 简体中文

一个 macOS 菜单栏隐私屏工具：拉上幕布，实体屏幕全黑，AI agent 在幕后继续工作。

Curtain 保持当前桌面会话可用，通过显示器 gamma 控制隐藏实体输出。兼容的工具仍能访问桌面，包括已测试的 Codex Computer Use 截图和点击路径。兼容性取决于显示器、采集方式和输入工具，详见[使用边界与恢复](#使用边界与恢复)。

> **Curtain 只是视觉隐私工具，不是真正的系统锁屏，不能作为安全锁屏的替代。** 桌面会话仍在运行，兼容的截图和自动化工具仍可访问桌面。即使使用 Touch ID／密码验证和本地输入拦截，也不具备 macOS 系统锁屏的安全保障。保护敏感内容或防止未经授权的访问时，请按 **Control–Command–Q** 使用 macOS 系统锁屏。
>
> **实验性项目，请自行评估使用风险。** Curtain 可能存在 bug，不保证隐私或安全。画面可能意外露出，本地输入也可能传入应用。

## 功能

- 遮挡实体屏幕，兼容的截图工具仍能看到桌面。
- 使用 Touch ID 或 macOS 登录密码恢复显示。
- 拉幕时拦截实体键盘和鼠标输入，需要辅助功能权限。
- 拉幕期间阻止显示器空闲睡眠。
- 独立守护进程在应用无响应时执行恢复。

## 安装发布版

目标平台为 **Apple Silicon（arm64）**，最低运行版本为 macOS 15。实体显示器测试在 macOS 26 上完成；macOS 27 虚拟机有限测试覆盖了权限、密码解锁、会话清理和渲染回归，不代表实体屏幕遮挡已验证。macOS 15 仍未验证。详见[验证记录](docs/verification.md#2026-11-09-macos-27-virtual-machine-validation)。

有可用安装包时，从 [GitHub Releases](https://github.com/iwaller/curtain/releases) 下载 `Curtain-arm64.dmg`，打开后将 **Curtain** 拖到 **Applications（应用程序）**，推出磁盘映像，再从应用程序目录启动。也可使用 ZIP 手动安装。发布版使用本地代码签名，未经过 Apple 公证。如果首次启动被系统拦截，请前往 **系统设置 → 隐私与安全性 → 仍要打开**，再确认打开；受管理的 Mac 可能不允许此操作。

如果发布页尚无安装包，请[从源码构建](#构建与运行)。GitHub 自动生成的源码压缩包不是可直接安装的应用。

幕布打开时，可通过 **检查更新…** 查找 GitHub Releases 上的较新正式版本，并确认安装。自动更新要求发布版同时附带 `Curtain.zip` 和 `Curtain.zip.sig`。更新包通过独立的发布者签名验证，也支持 ad-hoc 签名的应用。辅助功能权限与更新签名独立，更新后可能需要重新授权。

## 构建与运行

请在 Apple 芯片 Mac 的原生终端中构建，并安装支持 Icon Composer `.icon` 资源的完整 Xcode。仅安装 Command Line Tools 不够。已验证的工具链为 macOS 26.7.1 上的 Xcode 27.1 / Swift 6.4，旧版工具链尚未验证。在 **Xcode → Settings → Locations → Command Line Tools** 中选择该 Xcode 安装。macOS 15 是应用的最低运行目标，不代表构建环境要求。

支持英文和简体中文，跟随 macOS 语言偏好。也可在 **系统设置 → 通用 → 语言与地区 → 应用程序** 中单独设置 Curtain 的语言，其他语言默认使用英文。

在仓库根目录构建并启动：

```bash
./scripts/build.sh
open build/Curtain.app
```

如果已有另一个副本运行，请先拉开幕布并退出旧副本，再启动构建结果。需要安装到 `/Applications` 并重启时，在构建后执行 `./scripts/install.sh`；运行中的实例未处于幕布打开状态时，脚本会拒绝替换。

构建优先使用可用的 Apple Development 签名证书，没有时使用 ad-hoc 签名。不需要第三方库。默认启用发布优化；调试构建可使用 `CURTAIN_BUILD_CONFIGURATION=debug ./scripts/build.sh`。

没有签名证书时，可执行 `CURTAIN_SIGN_IDENTITY=- ./scripts/build.sh`，生成的压缩包位于 `build/Curtain.zip`。发布者请按[发布流程](docs/operations/releasing.md)生成安装 DMG 和自动更新必需的签名文件。

## 使用

1. 打开 Curtain，按权限引导启用本地输入拦截。macOS 26 及更早版本称为**辅助功能**；macOS 27 及以后，应用使用**设备控制和数据访问**名称。未授权时仍可遮挡画面，但不会拦截本地输入。
2. 点击菜单栏中的 **开启隐私屏**。开启后有两秒宽限，避免刚才的点击立即唤出解锁界面。
3. 移动鼠标或按键唤出解锁界面，使用 Touch ID 或登录密码解锁。远程使用时，从菜单选择 **解锁…**。

菜单栏应用默认不设会话时长上限。解锁界面 20 秒无操作后自动回黑。登录密码通过 macOS OpenDirectory 在本机校验，Touch ID 使用 LocalAuthentication；Curtain 不保存密码，也不将密码写入日志。

权限引导在空间充足时显示于系统设置窗口外，空间不足时使用左侧紧凑卡片。点击 **×** 可收起引导，点击返回箭头可回到设置引导主窗口。

系统锁屏、睡眠或切换用户会话会结束隐私会话并恢复显示；解锁 macOS 后不会自动重新开启 Curtain。阻止显示器空闲睡眠不能阻止合盖或强制睡眠，无人值守时请让笔记本保持开盖并接通电源。

## 使用边界与恢复

**Curtain 用于视觉隐私，不能代替 macOS 系统锁屏。** 远程截图仍可能看到桌面。需要系统锁屏时，请按 **Control–Command–Q**。

显示解锁界面时，Curtain 会恢复 gamma，并用窗口遮挡桌面，让认证控件可见。这段时间内切换 Space 或全屏仍可能露出内容，认证面板也可能干扰 agent 输入。

已测试单屏原生全屏过渡，以及镜像双屏下的 Space 切换。扩展桌面、HDR、热插拔、整夜运行，以及开启输入拦截后的完整 agent／远程操作兼容性仍待验证，详见[验证记录](docs/verification.md)。

主线程约 10 秒没有心跳时，守护进程会先尝试系统锁屏，最多等待三秒确认，再结束 Curtain，恢复显示和输入。故障锁屏使用 macOS 私有接口，可能失败，此时优先恢复可操作性。普通崩溃或强制结束进程不保证触发系统锁屏。兜底可从 `~/Library/Logs/Curtain/curtain.log` 获取 PID，执行 `kill -TERM <pid>`；无响应时使用 `kill -KILL <pid>`。结束 Curtain 会恢复画面，除非 macOS 已锁屏。

## 开发

- [架构地图](docs/architecture.md)
- [子系统索引](docs/subsystems/README.md)
- [实验方案](docs/poc-plan.md)

实验 CLI 是独立的视觉测试工具，不提供输入拦截、密码／Touch ID 解锁界面或心跳守护。默认运行 90 秒，可设置为 1–300 秒。启动前请记住退出办法：到时自动结束；提前结束可在启动终端按 **Control–C**，或用启动日志中的 PID 执行 `kill -TERM <pid>`。退出后恢复显示。请仅在没有 Curtain 隐私会话运行时执行：

```bash
./build/curtain-poc --gamma --duration 90
```

构建还包含两个辅助程序：隐私会话期间负责故障恢复的 `CurtainWatchdog`，以及处理解锁背景图后即退出的 `CurtainRenderer`，均不安装为常驻服务。渲染失败时使用深色渐变背景。组件内存评测及适用范围见[验证记录](docs/verification.md#2026-11-07-disposable-wallpaper-renderer-integration)。

## 致谢

本项目的 `LESSONS.md`、`AGENTS.md` 和 `docs/` 目录中的文档组织方式与协作实践借鉴了 [yetone](https://github.com/yetone) 的 [Magpie](https://github.com/yetone/magpie) 项目。Magpie 使用 [MIT 协议](https://github.com/yetone/magpie/blob/main/LICENSE)。

权限引导交互（包括浮动拖动条及其飞入动画）经由 Barlet 借鉴了 [zats](https://github.com/zats) 的 [Permiso](https://github.com/zats/permiso) 项目。
