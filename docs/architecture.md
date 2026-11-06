# 架构：入口、职责与当前状态

本项目采用最小原生 Swift/AppKit 应用。保持当前 macOS 登录会话可用，在其上显示视觉遮罩，验证现有 Computer Use 的采集和输入路径。

## 实现状态

| 能力 | 当前状态 | 归属 |
| --- | --- | --- |
| agent 协作规范、需求分析、实验步骤 | 已完成文档 | [AGENTS.md](../AGENTS.md)、[实验方案](poc-plan.md) |
| 实验 CLI `curtain-poc` | 已编译 | [POC](../Sources/POC/main.swift)、[构建脚本](../scripts/build.sh) |
| 菜单栏应用 `Curtain.app`（第一版第 1、2 步） | 已编译，启动/退出已检查；拉上幕布未实机验证 | [菜单栏子系统](subsystems/menu-bar-app.md) |
| 每显示器黑色覆盖窗口、限时退出 | 已实现；单显示器启动/退出实测 | [遮罩子系统](subsystems/privacy-overlay.md) |
| Computer Use 截图与点击兼容性 | 普通遮罩下截图可读、坐标点击通过 | [验证子系统](subsystems/computer-use-validation.md) |
| Space、全屏切换及返回后的覆盖 | 工具侧可操作；全屏过渡覆盖失败，4 项修复对照均失败，已回退；普通 Space 与实体待测 | [实验方案](poc-plan.md) |
| Gamma 清零模式 `--gamma` | 2026-11-05 现场通过：实体全黑、原生全屏进出不闪、Computer Use 截图与点击有效；Space/UU/多显示器未测 | [遮罩子系统](subsystems/privacy-overlay.md) |
| 密码、菜单栏、输入限制 | 后续评估 | [路线图](roadmap.md) |

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

[build.sh](../scripts/build.sh) 通过 `xcrun swiftc` 编译，输出实验 CLI `build/curtain-poc` 和 ad-hoc 签名的 `build/Curtain.app`；共享代码在 `Sources/Shared/`（gamma 清零、日志），应用代码在 `Sources/App/`，`Resources/Info.plist` 设 `LSUIElement`。测试页为 [click-test.html](../fixtures/click-test.html)，不需要临时服务器。截图、桌面状态和运行日志归忽略的 `artifacts/`，脱敏实测结论见 [验证记录](verification.md)。

## 修复对照后的状态

跨应用角色、非激活面板、独立跨应用面板和 CoreGraphics 显示器捕获都没有通过全屏过渡覆盖，实验改动已回退。窗口轨迹确认至少一轮进入全屏时，遮罩随旧 Space 横向移走；当前源码只增加毫秒日志，尚未修复该问题。结果与后续路线边界见 [验证记录](verification.md)。
