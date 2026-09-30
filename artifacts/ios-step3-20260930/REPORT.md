# 第三步：iPadOS 27.0 真机 Debug 验收

## 结论

**通过用户指定的第三步验收。** 已完成源码构建、签名安装、启动、Dart 断点调试、修改后的热重载、目标问题复现和日志导出。目标问题仅复现，没有修复；未执行第四至六步。验收通过后，用户授权将源码适配和本报告提交到当前 worktree。

## 本次运行基线

| 项目 | 实际值 |
| --- | --- |
| 日期、时区 | 2026-09-30，Asia/Shanghai |
| 源码 commit | `78bbaf4cfa1f5f32092f6894123f6009fc220fae` |
| 本次附加源码 | 本提交纳入的 UIScene 启动适配，验收时保存的 [完整补丁](source-changes.patch) |
| 设备 | ZYZ’s iPad Pro，iPad Pro 11-inch (M4)，`iPad16,3` |
| 系统 | iPadOS 27.0，build `24A437` |
| 连接、准备状态 | USB；paired、connected；Developer Mode 已启用；已解锁 |
| Xcode | 27.0，build `27A266a` |
| Developer Disk Image | 已挂载；compatible、usable；build `27A266a` |
| Flutter / Dart | 3.47.3 / 3.13.3 |
| 构建模式 | 真机 `Debug`，`iphoneos`，arm64 |
| 本地 Bundle ID / Team | `com.fuhua.erosfe.step3` / `A9798656MR` |
| 签名 | Apple Development；已生成 embedded provisioning profile |

签名配置保存在被 Git 忽略的 `ios/Flutter/Local.xcconfig`。本次运行不是仅靠上述 commit 的未修改构建，复现版本须同时包含所附 UIScene 补丁。

## 验收证据

本报告随源码提交。以下链接指向本机 `artifacts/ios-step3-20260930/` 下保存的原始验收产物；日志、截图、设备信息和崩溃报告保留在本地证据目录。

| 条件 | 实际操作与结果 | 文件索引 |
| --- | --- | --- |
| USB 设备可用于开发 | CoreDevice 读取设备、解锁状态和 DDI；DDI 自动挂载成功 | [设备](device-details.json)、[解锁](device-lock.json)、[DDI](ddi-services.json) |
| 开发签名可用 | 用户重新登录 Xcode 开发账号后，自动签名、构建与安装成功 | [签名](code-signing-uiscene.txt)、[完整运行日志](flutter-debug-session-uiscene.log) |
| 从源码启动 Runner | UIScene 适配后的 Xcode 构建用时 11.2 秒，安装启动 25.0 秒；执行到 Dart `main` | [关键开发日志](development-evidence.log)、[VM 证据](dart-debug-proof.json) |
| Dart 调试 | VM 主 isolate 连接成功，求值 `kDebugMode == true`；磁力按钮源码第 171 行断点命中，保存调用栈后移除断点并恢复执行 | [断点与调用栈](dart-breakpoint-proof.json)、[调试工具日志](dart-debug-probe.log) |
| 修改后热重载 | 临时加入 `reassemble()` 日志探针，热重载 1 个库，792ms，并打印探针；移除探针后再次热重载成功，484ms | [探针补丁](hot-reload-probe.patch)、[关键开发日志](development-evidence.log) |
| 原生日志 | 捕获 Objective-C、Flutter 原生渲染和 Scene 生命周期日志 | [原生日志](native-console.log) |
| 复现并导出 App 日志 | 用户操作红色磁力按钮并确认分享菜单未出现；捕获相应 PlatformException | [问题日志](magnet-reproduction.log)、[App 控制台日志](app-console.log)、[用户确认](user-reproduction-confirmation.txt) |
| 留存原生崩溃报告 | 保存适配前启动失败的 5 份 `.ips`；复现后未发现新增 fehviewer 原生崩溃报告 | [启动失败列表](crash-after-launch.json)、[复现后列表](crash-after-reproduction.json)、[结果](reproduction-result.json) |

`lib/main.dart` 的热重载探针已移除，磁力按钮 Dart 文件与基准 commit 相同。`pubspec.lock`、`ios/Podfile.lock`、`Gemfile.lock` 未改变，见 [锁文件状态](lockfile-state.json)。

## 目标问题复现

1. 在当前 USB 真机 Debug App 中打开含种子的画廊。
2. 打开种子子菜单。
3. 点击红色磁力按钮。
4. Dart 断点命中 `lib/pages/gallery/view/torrent_dialog.dart:171` 的 `Share.share(_magnet)`；抓取调用栈后自动恢复。
5. 用户确认：**“点击完成，仍未出现分享菜单”**。

断点命中时间为 **21:44:08（本地时间）**。恢复后运行日志记录：

```text
PlatformException(error, sharePositionOrigin: argument must be set,
{{0, 0}, {0, 0}} must be non-zero and within coordinate space of source view:
{{0, 0}, {1210, 834}}, null, null)
```

异常栈经过 `StandardMethodCodec.decodeEnvelope`、`MethodChannel._invokeMethod`、`MethodChannelShare.share`。据源码断点、异常和用户反馈，可以确认当前分享调用在 iPad 上被位置参数校验拒绝；本次未修改该调用。保存了 [操作后的设备截图](after-magnet-tap.png)。

本次 App 的 `Documents/log` 目录为空，已核对并导出该目录；有效的应用日志来自 Flutter 捕获的 stdout/stderr，保存在 `app-console.log` 和完整运行日志中。原始日志中的网络错误未从完整记录中删除。

## 为完成启动所需的源码修改

适配前 Runner 在 Dart VM 启动前原生崩溃。系统栈顶为 `___UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption_block_invoke`，终止类型为 `EXC_BREAKPOINT / SIGTRAP`。Flutter [UIScene 官方迁移说明](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate)也说明了 Xcode 27 构建的 UIKit App 对 UIScene 生命周期的要求。

| 源码文件 | 修改内容 |
| --- | --- |
| `ios/Runner/AppDelegate.swift` | 实现 `FlutterImplicitEngineDelegate`，在隐式引擎初始化回调注册插件；保留 downloader 的后台插件注册配置 |
| `ios/Runner/SceneDelegate.swift` | 继承 `FlutterSceneDelegate`，调用父类生命周期方法，并接收现有隐私遮罩的前后台回调 |
| `ios/Runner/Info.plist` | 增加单 Scene manifest，使用 Main storyboard 和本项目 SceneDelegate |
| `ios/Runner/SecurityBlurEffect.swift` | 接收 Scene 的 window，替换已不适用于此生命周期的全局 keyWindow 强制解包 |
| `ios/Runner.xcodeproj/project.pbxproj` | 将 SceneDelegate 加入 Runner 编译源文件 |

系统崩溃报告均保存在 `crashes/`：

- [fehviewer-2026-09-30-213035.ips](crashes/fehviewer-2026-09-30-213035.ips)
- [fehviewer-2026-09-30-213035.000.ips](crashes/fehviewer-2026-09-30-213035.000.ips)
- [fehviewer-2026-09-30-213035.0002.ips](crashes/fehviewer-2026-09-30-213035.0002.ips)
- [fehviewer-2026-09-30-213052.ips](crashes/fehviewer-2026-09-30-213052.ips)
- [fehviewer-2026-09-30-213143.ips](crashes/fehviewer-2026-09-30-213143.ips)

## 本次结果的范围

这份通过结论对应用户修改后的第三步及上述设备、系统和源码状态。运行记录仍有 FileUtils 重名、插件使用旧生命周期、部分下载路径权限错误和网络 403 等提示；本次没有处理这些独立问题。隐私遮罩的完整回归、iPhone 对照、模拟器验证和 CI 均未纳入本次验收。

临时断点已移除，热重载探针已还原，Flutter 调试连接已正常 detach。源码适配和本报告随本次提交记录，原始证据文件保留在本地工作树中。
