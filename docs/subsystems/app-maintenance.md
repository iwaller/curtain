# 更新、关于与权限引导

2026-11-06：更新、关于、权限引导已实现；按 Barlet 重写的权限卡片与独立拖动条已按用户后续要求安装并重启。生产视图已生成明暗原生渲染预览，用户已要求重置本应用的辅助功能权限以测试，完整 GUI 验收仍待测。主审此前读取安装应用超时（-10005），不计为 GUI 通过；详见验证记录。无第三方依赖。

源码：[Updater.swift](../../Sources/App/Updater.swift)、[UpdatePackage.swift](../../Sources/App/UpdatePackage.swift)、[AppVersion.swift](../../Sources/App/AppVersion.swift)、[PermissionGuide.swift](../../Sources/App/PermissionGuide.swift)，菜单集成在 [CurtainApp.swift](../../Sources/App/CurtainApp.swift)。

## Distribution

Apple Silicon (arm64) is the only supported architecture. The build explicitly targets arm64 and requires a native Apple Silicon build host. DMG packaging checks that both the app and watchdog contain only arm64 code. The installer name includes the architecture; update asset names remain `Curtain.zip` and `Curtain.zip.sig` because there is a single supported architecture.

Decision confirmed by the user on 2026-11-06: distribute `Curtain-arm64.dmg` for initial installation, with `Curtain.zip` and `Curtain.zip.sig` for in-app updates, without App Store submission, Developer ID distribution signing, or Apple notarization. A local code signature is not Apple approval; downloaded copies may be blocked by Gatekeeper on first launch.

The existing build prefers an available Apple Development identity to preserve local Accessibility authorization across rebuilds, and falls back to ad-hoc signing. `CURTAIN_SIGN_IDENTITY=- ./scripts/build.sh` explicitly produces an ad-hoc package without a signing certificate. Both the app and its watchdog are signed before packaging. Changing signing identity or rebuilding an ad-hoc app may require Accessibility authorization again.

Installation: open `Curtain-arm64.dmg`, drag `Curtain.app` onto its Applications shortcut, eject the volume, and open the installed app. The ZIP remains an alternative for manual installation. `package-dmg.sh` copies only the signed app and an `/Applications` symlink into a compressed, read-only HFS+ image; the updater continues to consume the ZIP, whose archive contract rejects symlinks. The image contains neither signing tools nor private keys. `package-release.sh` creates all three release attachments from the same build; a successful rebuild removes stale DMG/signature outputs.

If macOS blocks the launch, open System Settings → Privacy & Security → Open Anyway, authenticate if prompted, and confirm Open. Availability and wording depend on macOS and device policy; approval on a separate Mac with a quarantined download remains unverified. Do not require users to disable Gatekeeper globally.

The updater authenticates releases using Ed25519 independently of Apple signing. Ad-hoc and local Apple Development builds both support the existing check → consent → automatic download/install/restart flow. First-launch approval, Gatekeeper policy, and Accessibility authorization remain separate macOS decisions; cross-Mac installation and authorization retention still need live testing. Release procedure: [releasing.md](../operations/releasing.md).

## 更新契约

- 仅菜单“检查更新…”触发检查；没有后台定时检查、静默下载或自动强制拉开幕布。发现新版后由用户选择下载安装、稍后或打开发布页面。
- 只有 open 可检查/安装。整个检查、确认、下载、校验期间禁止新拉幕（包括菜单延迟调用）；closed、unlocking、recovering 禁止更新、关于和权限入口。原子交换前同步再次检查状态和取消标志。
- Release metadata comes from `https://api.github.com/repos/iwaller/curtain/releases/latest`; pages and initial attachment URLs must belong to `https://github.com/iwaller/curtain/releases`. Only attachment downloads may redirect to the exact HTTPS hosts `release-assets.githubusercontent.com` or `objects.githubusercontent.com`, on port 443. Credentials and fragments are rejected. Other configured servers retain the same-origin policy. TLS verification remains enabled.
- HTTP 404 表示尚无可用发布，显示失败原因和发布页入口，不能提示“已是最新版”。成功解析稳定版本后，仅发布版本号不高于当前版本时提示最新版。草稿、预发布和非数字版本拒绝。
- Each release must contain exactly one `Curtain.zip` (at most 256 MiB) and one `Curtain.zip.sig` (at most 4 KiB). The latter contains a Base64-encoded, 64-byte Ed25519 signature over the exact ZIP bytes. Missing, malformed, oversized, mismatched, or tampered signatures fail before archive parsing or extraction.
- 系统 libarchive tar 解压：仅允许 `Curtain.app` 内普通文件与目录，拒绝绝对路径、`..`、符号/硬链接、其他根目录，最多 10,000 项及 1 GiB 展开体积；默认安全解压，不使用 `-P`。本应用包不需要框架符号链接，未来包结构变化须一起调整契约与测试。
- The publisher public key is maintained in `Resources/UpdatePublicKey.txt`, validated and compiled into the executable as `UpdateTrust.publicKey` by the build. Candidate packages and release metadata cannot replace the running verifier's trust root. The build also records it in `CurtainUpdatePublicKey` for publisher tooling and continuity checks; updates must retain the same key. App and helper code signatures still require strict, nested, all-architecture integrity, but no Apple Team ID. Bundle ID, entry point, release version, increasing version, minimum macOS version, and both CPU architectures remain checked. Key rotation is not automatic; changing or losing the key requires manual installation of a new trust root.
- 下载、解压、签名校验不改当前应用。staging 在应用同卷；`renamex_np(RENAME_SWAP)` 一次交换新旧目录。交换失败保留原应用；重启信号发送失败时尝试交换回原应用；极端回滚失败保留 staging 中旧版本并明确提示手动重开，不能按普通失败删除旧版。
- 取消在最终交换前有效。后台解压/校验结束后再次检查取消，不继续安装；取消和失败均清理 staging/进度窗口并解除忙碌。退出会取消任务并等待清理后回复 AppKit。已经交换成功属于提交点，不再提供取消按钮。
- 独立短命 shell 只有收到交换成功信号后才等待旧进程退出（最多 30 秒），随后打开新版并清理旧版；交换失败/EOF 不启动新版。等待超时不强制杀进程，留下暂存版本，下次手动启动生效。新版从 open 启动，不保存或恢复 closed 会话。

## 关于与窗口所有权

The About panel uses the English label `Commit` in both supported languages and has no personal-use notice.

“关于 Curtain”使用系统标准面板，展示应用名、短版本、构建号，附提交短哈希（含未提交文件时加 `-dirty`）。构建号为 git 提交数，发布短版本仍手动维护。

只跟踪标准调用创建的关于 NSPanel，并在拉幕前隐藏此面板及自身权限窗口。**不得遍历隐藏 NSApp.windows**：NSStatusBarWindow 也在其中，隐藏会让 UU 无法点击“解锁…”。keyWindow 赋值可能异步，不用它立即定位新建关于面板。临时原生 AppKit 探针已确认定向隐藏后状态栏仍可见；不是 UU 坐标点击或完整幕布现场验收。

## 权限契约

- 只引导辅助功能：用于拦截实体输入和唤出解锁界面，不申请屏幕录制等 Barlet 专有权限。未授权首次启动显示说明，可点“稍后设置”。菜单参照 Barlet：仅缺权限时显示“允许拦截本地输入…”，授权后隐藏，撤销后重新出现；打开菜单时立即读回权限，旧菜单动作也须重验并拒绝在已授权时重新打开引导。
- 主窗口参考 Barlet：440 pt 固定宽、32 pt 内容边距、透明隐藏标题栏、一张横向权限卡片。未授权显示“允许”和一句降级说明；已授权只显示绿色勾选“已允许”、下次拉幕生效提示与“完成”，不保留禁用设置按钮、拖放区或未授权文案。macOS 27 使用“设备控制和数据访问”名称。
- 用户点击卡片“允许”后才打开系统辅助功能页，**保留主窗**，独立 440×104 pt 拖动条由按钮位置沿弧线飞入设置窗口，采用与 Barlet 相同的 0.72 秒阻尼弹簧、缩放和淡入；系统“减少动态效果”开启时直接呈现终态。条内提供返回按钮、单行提示与可拖动的 Curtain 应用行。每 0.5 秒读取前台设置窗口边界以跟随，离开设置后隐藏并停轮询（首次启动最多等 5 秒），重新激活时恢复。不开启第二个 AX 系统提示，不主动修改权限或重启应用。
- 拖动使用 Barlet 的整行快照及原始 bounds，拖出时原行留空、结束后恢复；不是单个图标从固定原点跟随。拖动期间暂停位置查询和跟随，避免原生拖放 run-loop 内重复抬升/移动面板。切走、返回、收起、授权成功均停止飞入 display link，避免残留动画回调。
- 返回会重新显示主窗口；关闭主窗、主动收起或授权成功会清理拖动条、计时器和观察者。授权轮询不激活或重新弹出主窗；撤销权限后可从恢复显示的菜单入口重新打开。已打开的主窗在授权后显示确认状态；授权/撤销可在同一个主窗实例中切换，无灰色操作占位。
- 每秒只读查询授权变化，刷新状态；授权/撤销不主动创建、移除或切换当前会话的输入 tap，不恢复 gamma、不弹窗口。下次正常拉幕时重新尝试创建 tap。缺权限时保留“只遮画面、不拦截输入”的降级行为；系统撤销既有 tap 的行为仍由 macOS 决定。
- 拉幕前收起引导。closed/unlocking/recovering 或更新忙碌时不能显示引导或打开设置。授权后状态若未刷新，可先正常拉开幕布，再手动退出重开；不擅自重启隐私会话。

## Localization

Following Barlet's native localization approach, user-facing strings use English keys with `String(localized:)`. Translations live in `Resources/en.lproj/Localizable.strings` and `Resources/zh-Hans.lproj/Localizable.strings`. `Info.plist` declares English as the development region and lists both supported languages; the build copies these directories before signing and packaging the app.

macOS selects the language using the user's preferred languages or per-app language setting. Unsupported languages fall back to English. There is one app bundle with both languages; no custom language switcher or separate language builds. Menus, setup and permission states, accessibility labels, unlock controls and Touch ID messages, update progress and errors are localized. Release notes retain the publisher's language; technical logs and the experimental CLI remain unchanged.

The primary menu action is “Enable Privacy Screen” / “开启隐私屏”. The unlock date uses the selected app language and a localized date template; the time uses the user's regional format. Permission content resizes when grant/revoke text wraps differently. Changes affect presentation only; authentication, input filtering, gamma control and recovery ordering remain unchanged.

`python3 scripts/test-localizations.py` checks the built app and release archive, interpolation placeholders, native language negotiation (English, Simplified Chinese and unsupported-language fallback), production permission states, and drag instruction width in isolated bundles. `./scripts/render-permissions.sh` renders production permission views under both languages to `artifacts/permission-redesign/{en,zh-Hans}/`. Neither launches the live controller nor modifies permissions or gamma. These checks do not establish end-to-end GUI acceptance.

## Validation

`python3 scripts/test-updates.py` 使用 build 内隔离包，覆盖版本/发布解析、URL、真实开发者签名解压保留、嵌套篡改/错误版本/身份/系统、恶意路径与链接、取消/隐私状态拒绝交换、系统交换失败和重启准备失败回滚、权限轮询及禁止呈现。没有真实更新服务器安装、权限拖放或实体屏幕验收。详细结果见[验证记录](../verification.md)。

`./scripts/render-permissions.sh`（先构建）编译独立 `PermissionPreview.app`，直接构造生产的 PermissionWindow / PermissionDragPanel 并用 AppKit 离屏绘制到 `artifacts/permission-redesign/`。未授权、已授权、拖动引导各有明暗两张图，另有同窗授权/撤销切换预览；不会启动 CurtainController、显示窗口、打开设置或更改权限。非激活窗口的交通灯/默认按钮状态及缺少桌面阴影属于离屏预览限制，不代表真实点击/授权验收。

`./scripts/test-permission-interactions.sh` 是原生组件回归：短暂显示测试自有窗口，用无操作替身代替打开系统设置；验证“允许”保留主窗、失效按钮受状态约束、拖动条整行文件快照，以及实际 display-link 飞入推进/完成/中途停止。它不是 Computer Use 点击或真实授权拖放验收。渲染脚本还输出 `flight-{start,middle,end}-{light,dark}.png` 与 `drag-snapshot-{light,dark}.png`，用于检查生产动画姿态和原生拖动图像。
