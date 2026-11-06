# 架构：入口、职责与当前状态

本项目采用最小原生 Swift/AppKit 应用。保持当前 macOS 登录会话可用，在其上显示视觉遮罩，验证现有 Computer Use 的采集和输入路径。

## 实现状态

| 能力 | 当前状态 | 归属 |
| --- | --- | --- |
| agent 协作规范、需求分析、实验步骤 | 已完成文档 | [AGENTS.md](../AGENTS.md)、[实验方案](poc-plan.md) |
| 实验 CLI `curtain-poc` | 已编译 | [POC](../Sources/POC/main.swift)、[构建脚本](../scripts/build.sh) |
| 菜单栏应用 `Curtain.app` | 本地解锁、20 秒回黑、UU 密码解锁已实测；输入拦截后的 Codex/UU 完整回归待测 | [菜单栏子系统](subsystems/menu-bar-app.md) |
| 手动更新、关于、权限引导 | 已实现；签名包与隔离替换/取消回归通过，完整 GUI/真实发布安装待验；发布源当前尚不可用 | [应用维护](subsystems/app-maintenance.md) |
| 心跳守护与故障锁屏 | 已实现；主线程每秒心跳，约 10 秒超时后请求系统锁屏并结束 Curtain；替代菜单栏默认 300 秒限制，验收见验证记录 | [故障恢复](subsystems/recovery-watchdog.md) |
| 每显示器黑色覆盖窗口、限时退出 | 已实现；单显示器启动/退出实测 | [遮罩子系统](subsystems/privacy-overlay.md) |
| Computer Use 截图与点击兼容性 | 普通遮罩下截图可读、坐标点击通过 | [验证子系统](subsystems/computer-use-validation.md) |
| Space、全屏切换及返回后的覆盖 | gamma 单屏全屏、镜像双屏普通 Space 往返及解锁界面 Space 变化回黑现场通过；旧窗口遮罩曾失败，仍不能保证所有过渡零闪露 | [菜单栏子系统](subsystems/menu-bar-app.md) |
| Gamma 清零模式 `--gamma` | 单屏及 1920×1080 实体镜像双屏普通 Space 现场通过；逐屏失败回滚模拟通过；扩展模式/HDR/热插拔第一帧待测 | [遮罩子系统](subsystems/privacy-overlay.md) |
| 本地输入拦截 | closed 拦截、unlocking 放行；本地现场通过 | [输入拦截](subsystems/input-guard.md) |

## 运行路径

```text
手动启动 Swift/AppKit POC
          |
          v
   遮罩生命周期控制器 ----> 超时退出 / 进程结束
          |
          +----> 每显示器一个黑色无边框 NSWindow
          |       高窗口层级 / 跨 Space / 不抢键盘焦点
          |
          +----> 实体显示器：观察是否持续黑色覆盖

Codex Computer Use
          |
          +----> 应用窗口截图 / 辅助功能树（分别验证）
          +----> 坐标点击 / 辅助功能点击（分别验证）
                              |
                              v
                    Safari 专用本地测试页面
                              |
                              v
                       可见点击计数与状态
```

工具是否会激活或抬高目标应用、是否截取独立应用窗口、截图是否包含遮罩，均由实验确定。上图描述测试对象，不承诺底层采集机制。

## 模块与数据边界

首版只需要应用入口、遮罩窗口生命周期、简单测试页面和运行记录。不引入服务端、账号、第二登录会话、网络模型调用或系统认证修改。

[POC](../Sources/POC/main.swift) 包含参数解析、应用入口与主线程生命周期。自动退出 Timer、SIGINT/SIGTERM 处理先于遮罩安装；窗口使用 screenSaver 层级（本机 1000），不激活应用，不成为 key/main window，鼠标穿透。显示器参数变化时重建窗口，但热插拔尚未实测。

[build.sh](../scripts/build.sh) 通过 `xcrun swiftc` 编译，输出实验 CLI `build/curtain-poc`、`build/Curtain.app` 及其 `Contents/Helpers/CurtainWatchdog`；优先 Apple Development 证书，缺失时 ad-hoc。共享代码在 `Sources/Shared/`（gamma 清零、日志），应用代码在 `Sources/App/`，独立守护在 `Sources/Watchdog/`；`Resources/Info.plist` 设 `LSUIElement`。测试页为 [click-test.html](../fixtures/click-test.html)，不需要临时服务器。截图、桌面状态和运行日志归忽略的 `artifacts/`，脱敏实测结论见 [验证记录](verification.md)。

菜单栏应用在清零 gamma 前启动守护并等待 ready；closed/unlocking 期间仅主线程发送心跳。守护先回复故障已提交 `F`，再由短命子进程调用系统私有锁屏入口，限时确认后结束父进程，不再主动暂停父进程。正常恢复须确认撤销守护；收到 `F` 时延后清理和退出，防止晚到的正常解锁先恢复桌面。守护自身退出时，仍可由恢复运行的主线程收尾。锁屏请求失败仍优先恢复可操作性，不承诺安全锁屏；详见[恢复契约](subsystems/recovery-watchdog.md)。

显示管线边界为 [DisplayGamma.swift](../Sources/Shared/DisplayGamma.swift)：全部在线显示器均清零成功且读回全零才视为启动成功。运行中失效、首次拉上或回黑失败时，组件暂停监测、保留曲线和 lease，由 owner 先协调守护再恢复；收到 F 时进入 recovering，禁止提前回滚，守护退出后仍可统一收尾。CLI 无守护，立即回滚并退出 1。解锁界面依据屏幕快照布置；恢复 gamma 前核对快照和已排队的 F，Space 或屏幕拓扑改变后尝试回黑并作废旧认证。实际热插拔和过渡最初几帧仍需实体观察，不能由通知/巡检机制推断零闪露。

[GammaLease.swift](../Sources/Shared/GammaLease.swift) 使用同一用户的持久锁文件与内核 flock，保证同时只有一个 Curtain gamma 控制者；未取得控制权的菜单栏/CLI 实例不能清零或恢复其他实例的曲线，CLI 拒绝启用返回 1。锁覆盖 gamma 实际生效区间，正常停止或进程结束时释放，不继承给 exec 子进程。

组合回归为 `python3 scripts/test-recovery-gamma.py`：使用真实守护管道协议、模拟显示曲线及锁屏替身覆盖上述清理顺序；不修改实体 gamma、不请求真实锁屏。

应用维护由 Updater 管理 open 状态下的手动检查、用户确认、下载和签名校验；UpdatePackage 负责安全解包与同卷原子交换，当前隐私会话绝不为安装而自动拉开。PermissionGuide 只说明并引导辅助功能授权，轮询不改变会话输入模式。构建脚本写版本元数据并输出 Curtain.zip；关于、权限窗口与状态栏窗口分别持有，禁止通配隐藏状态栏。契约及发布源边界见[应用维护](subsystems/app-maintenance.md)。

## 修复对照后的状态

跨应用角色、非激活面板、独立跨应用面板和 CoreGraphics 显示器捕获都没有通过全屏过渡覆盖，实验改动已回退。窗口轨迹确认至少一轮进入全屏时，遮罩随旧 Space 横向移走；当前源码只增加毫秒日志，尚未修复该问题。结果与后续路线边界见 [验证记录](verification.md)。
