# 代码与验证规范

## 首版实现范围

- 原生 Swift/AppKit，优先使用系统框架和公开 API；不为 POC 引入第三方依赖。
- 先检测本机 Swift/Xcode 工具链和 macOS 版本，再决定编译目标及构建命令；不要把尚未运行的命令描述成已经验证。
- AppKit 窗口生命周期在主线程处理。保持入口与遮罩控制清晰，不为一个简单实验引入插件系统或复杂架构。
- 命令参数须明确限定遮罩持续时间与实验模式；正常退出、超时退出均释放窗口和观察者。
- 日志记录时间、模式、显示器和生命周期事件，不采集用户页面正文、密码或完整辅助功能树。

## 可恢复性

显示遮罩前实现并验证自动关闭机制。应保留从终端结束进程的办法；不要只依赖可能被目标应用接收的 Escape 键。

POC 不修改系统锁屏、休眠或安全配置，不自动启动，不安装后台常驻服务。每轮结束恢复该轮主动改变的应用状态。

## 验证原则

编译验证与真实 GUI 验证分别记录。优先验证有意义的外部行为：遮罩持续存在、应用截图可读、坐标点击产生一次效果、跨 Space 后恢复、超时退出可用。

不要为文档骨架或对窗口属性逐行断言而新增测试。后续若有参数解析、状态转换或清理逻辑，再按风险补必要测试。

应用窗口截图不等于实体屏幕录像；辅助功能点击不等于坐标点击。不能用其中一个结果替代另一个。未经观察的多显示器、其他 macOS 版本、睡眠唤醒和切换用户均标为未验证。

## 文档维护

实际构建入口为 `./scripts/build.sh`（`xcrun swiftc -framework AppKit`），不需要第三方依赖，输出在忽略的 `build/`。

当前事实主要维护在 [架构地图](architecture.md) 和 [验证记录](verification.md)；设计契约维护在所属子系统。新增源码后补链接，行为变化同步更新。真实截图和日志置于忽略的 `artifacts/`，不写入仓库。

## Build configurations (2026-11-07)

`./scripts/build.sh` defaults to `release` with `-Osize -whole-module-optimization` for the app, CLI and watchdog. Use `CURTAIN_BUILD_CONFIGURATION=debug ./scripts/build.sh` for `-Onone -g`. Both configurations target arm64/macOS 15, use the existing signing/package flow and write the same build output paths; a build never installs or restarts the live app. Unknown configuration names fail before replacing the bundle. Existing regression harnesses compile production code with the release optimization flags; AddressSanitizer rendering checks are separate from performance measurements.
