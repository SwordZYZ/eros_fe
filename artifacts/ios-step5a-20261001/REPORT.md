# Step 5A：修复前回归基线

**5A 通过：修复前基线已建立，目标分享 Bug 仍未修复。** iPad 连续 3 次及 arm64 iPad 模拟器均按固定数据和真实调用链记录分享 FAIL；两端核心冒烟、真机两种遮罩状态的锁屏恢复均已记录。另有启动目录异常、四轮返回导航时的 `ScrollController` 已释放异常、第三轮真机的 4px `RenderFlex` 溢出、遮罩开启仍泄露清晰卡片，以及锁脚本退出异常，均单独保留 FAIL／问题记录。导航 PASS 仅表示成功返回，不能理解为导航无异常。

## 1. 源码和范围

- 测试时本地 `master` 与 detached worktree 均为 `d31e3561713c3d42fbdd7eb82b5dd53b96a972ad`，包含 Step 3、Step 4，以及 Pods 准备和构建／运行会话锁。
- 本次提交只新增 Debug 探针、宿主驱动、固定夹具和证据。生产文件、分享调用和三个依赖锁文件未改动。
- 实际测试源码 = 上述 commit + [完整源码补丁](source-changes.patch)。补丁包含三个新增文件，不会遗漏未跟踪测试源码。文件 SHA-256、冻结时间见 [源码清单](source-manifest.json)，收尾核对见 [源码校验](source-verification.json)。
- 证据目录沿用任务开始日期 `20261001`；正式运行跨到北京时间 2026-10-02，事件使用 UTC 时间。

## 2. 固定环境

| 项目 | 本次条件 | 证据 |
| --- | --- | --- |
| Xcode | 27.0 / `27A266a` | [环境检查](environment.log) |
| Flutter / Dart | 3.47.3 / 3.13.3，framework `e8113bf456` | [环境检查](environment.log) |
| CocoaPods | 1.16.2；Bundler 4.0.20；Ruby 4.0.7 | [准备日志](preparation-locked.log)、[环境检查](environment.log) |
| 真机 | iPad Pro 11-inch M4 / `iPad16,3`，USB | [设备信息](device-details-final.json) |
| 真机系统 | iPadOS 27.0 / `24A437` | [真机日志](ipad-3.log) |
| 模拟器 | iPad Pro 11-inch M5，arm64；iOS 27.0 / `24A434` | [runtime](runtimes-final.json)、[模拟器日志](simulator-1.log) |
| 模式 | 两端均为从源码启动的 Debug | 各轮 `.log` 和 JSON 中的 environment 事件 |
| 最低支持版本 | 15.6；与测试系统版本分别记录 | [环境检查](environment.log) |
| 本地签名 | team `A9798656MR`，bundle `com.fuhua.erosfe.step5a` | 本地忽略文件 `ios/Flutter/Local.xcconfig`；构建日志 |
| 账号 | 三次真机与模拟器均断言无在线账号凭据，不记录凭据值 | `no_online_account: PASS` |
| 应用自动锁 | `autoLockTimeout = -1`；系统锁屏仍实际执行 | 各轮 environment 事件 |
| 依赖 | `pubspec.lock`、`ios/Podfile.lock`、`Gemfile.lock` 与基点逐字节相同 | [锁文件核对](lockfile-state.json) |

真机 UDID：`00008132-000278923E99001C`。模拟器 UDID：`E3B49F40-CB5C-4CDC-A04D-35E0284103A8`。

所有准备和 Flutter 构建／运行通过 `scripts/ios_dev.sh` 串行执行，运行会话结束后才切换下一轮或 SDK。没有执行并发争锁验收；本次观察到的退出异常另见第 6 节。

## 3. 固定数据和真实调用链

| 数据 | 固定值 |
| --- | --- |
| 画廊 | gid `950000001`，`EROS Step 5A — Fixed Local Gallery` |
| 图片 | 复用 Step 4 固定 QR PNG，预填实际图片缓存 |
| 种子 | `step5a-fixed-local.torrent`，1.00 MiB，seeds 3 / peers 0 / downloads 1 |
| 磁力 | `magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567` |

数据及图片校验值见 [夹具清单](fixture-manifest.json)。这是合成数据，不执行种子下载。固定画廊和种子入口使用注入的数据和本地图片缓存，无需在线账号或实时网络返回。原应用启动仍可能发起其他网络请求，这些请求不作为固定用例的成功条件。

实际路径：`application.main()` → 真实 `GalleryPage` / `GalleryActions` → 原种子按钮 → 原 `showTorrentDialog()` / `TorrentItem` → 原红色磁力按钮 → 原 `Share.share(_magnet)` → share_plus 原生插件。

探针只替换远程数据加载，按钮由真实渲染位置的指针事件点击。没有伪造分享 MethodChannel，没有补 `sharePositionOrigin`，没有修改 UIScene 或业务生命周期代码。探针将未处理异常保留在 stdout 和 App Documents 的 JSON；异常仍记为 FAIL。

## 4. 目标业务断言和重复结果

断言固定为：**系统分享菜单出现且可用**。只有没有 Dart 异常不能判定通过；探针在这种情况下返回 `NEEDS_NATIVE_OBSERVATION`，需进一步观察原生菜单及操作。

每轮：全新 Debug 冷启动 → 固定本地画廊 → 种子子菜单 → 红色磁力按钮 → 等待并检查系统菜单。真机连续执行 3 次，同一补丁、同一数据、同一设备和系统 build。

| 轮次 | 结果 | 菜单状态 | 证据 |
| --- | --- | --- | --- |
| iPad 1 | **FAIL** | 系统分享菜单未出现，仍在种子对话框 | [JSON](ipad-1-share.json)、[截图](ipad-1-share.png)、[日志](ipad-1.log) |
| iPad 2 | **FAIL** | 同上 | [JSON](ipad-2-share.json)、[截图](ipad-2-share.png)、[日志](ipad-2.log) |
| iPad 3 | **FAIL** | 同上 | [JSON](ipad-3-share.json)、[截图](ipad-3-share.png)、[日志](ipad-3.log) |
| arm64 iPad 模拟器 | **FAIL** | 同上 | [JSON](simulator-1-share.json)、[截图](simulator-1-share.png)、[日志](simulator-1.log) |

每轮同时保留 `*-gallery.png`、`*-torrent.png`。汇总见 [分享基线](share-baseline.json)。真机还从 App Documents 导出 [第 1 轮](app-logs/ipad-1-events.json)、[第 2 轮](app-logs/ipad-2-events.json)以及 [第 3 轮收尾事件](app-logs/ipad-3-events.json)。

一致异常：

```text
PlatformException(error, sharePositionOrigin: argument must be set,
{{0, 0}, {0, 0}} must be non-zero and within coordinate space of source view:
{{0, 0}, {1210, 834}}, null, null)
```

模拟器 source view 尺寸为 `{834, 1210}`。业务源码定位：[torrent_dialog.dart:171](/Users/fuhua/.codex/worktrees/da3d/eros_fe/lib/pages/gallery/view/torrent_dialog.dart:171)。当前锁定的 share_plus 为 11.1.0；本地原生源码 `FPPSharePlusPlugin.m:468` 在 iPad popover origin 为空或越界时返回同一 FlutterError 并提前退出。这与三次真机异常及截图一致。

## 5. 小规模冒烟基线

| 用例 | 模拟器 | iPad 真机 | 证据 |
| --- | --- | --- | --- |
| 冷启动进入主页 | PASS | PASS，3/3 | 各轮 `cold_start` |
| 启动无未处理异常 | **FAIL** | **FAIL，3/3** | `startup_no_exception`，见第 6 节 |
| 无在线账号 | PASS | PASS，3/3 | `no_online_account` |
| 打开固定内容及种子菜单 | PASS | PASS，3/3 | 各轮 gallery / torrent JSON |
| 进入真实设置页 | PASS | PASS，3/3 | 真实 `LayoutSettingPage`；各轮 smoke JSON |
| 从内容及设置返回主页，再打开固定内容（仅导航结果） | PASS | PASS，3/3 | `back_navigation` / `settings_back` / `fixed_content`；不代表无异常 |
| 返回导航时无异常（日志观察） | **FAIL** | **FAIL，3/3** | 各轮 smoke JSON 的 `ScrollController` 已释放异常，见第 6 节 |
| 内容布局溢出（日志观察） | 未记录到同类异常 | **FAIL：第 3 轮底部溢出 4px**；第 1、2 轮未记录到同类异常 | [第 3 轮 smoke JSON](ipad-3-smoke.json)，见第 6 节 |
| 前后台恢复，原画廊保留且种子菜单可交互 | PASS | PASS，遮罩关闭 | [模拟器结果](simulator-1-lifecycle_end.json)、[真机结果](ipad-1-lifecycle_end.json) |
| 遮罩关闭，实际锁屏解锁 | — | PASS | [用户确认](manual-observations.json)、[结果](ipad-lock-off-result.json)、[恢复截图](ipad-lock-off-resumed.png) |
| 遮罩关闭的多任务卡片 | — | PASS，用户确认清晰 | [卡片截图](ipad-lock-off-observed.png)、[用户确认](manual-observations.json) |
| 遮罩开启，实际锁屏解锁及交互恢复 | — | PASS | [结果](ipad-lock-on-result.json)、[恢复截图](ipad-lock-on-resumed.png)、[用户确认](manual-observations.json) |
| 遮罩开启的多任务卡片 | — | **FAIL：仍清晰显示内容，没有模糊** | [用户原话及追问](manual-observations.json)、[开关断言](ipad-privacy-on.json)、`ipad-3.log` 原生值 `true` |

前后台通过实际切换到系统设置，再激活同一 App 完成。锁屏解锁由用户按物理键及自行验证身份完成。日志保存 inactive / hidden / paused / resumed，以及原生 `sceneDidEnterBackground`、遮罩布尔值、`sceneWillEnterForeground`、`sceneDidBecomeActive`。业务菜单恢复后再打开并关闭，避免只检查页面对象仍在内存。真机锁屏前后相关原生进程集合未变，见 [进程连续性](process-continuity.json)。关闭状态截图捕获了清晰的多任务卡片；开启状态的视觉 FAIL 来自用户两次明确回复，未将它描述为自动截图断言。

App 的 `Documents/log` 为 0 文件，见 [清单](app-logs/native-app-log-files.json)。因此原生与 Dart 调试日志保存在各轮完整 stdout，结构化事件另外导出到 `app-logs/`。

## 6. 目标用例以外的问题

### 启动下载目录异常：保留修复前 FAIL

两端均在创建相对路径 `Download` 时失败，但错误类型和 errno 不同：

| 环境 | 实际异常 | 证据 |
| --- | --- | --- |
| 模拟器 | `FileSystemException` / `Read-only file system` / `errno = 30` | [逐轮异常索引](non-target-issues.json) 的 `simulator-1.startup`、`simulator-1.log:107` |
| iPad 真机三轮 | `PathAccessException` / `Operation not permitted` / `errno = 1` | [逐轮异常索引](non-target-issues.json) 的 `ipad-1.startup`、`ipad-2.startup`、`ipad-3.startup`；日志分别为 `ipad-1.log:116`、`ipad-2.log:100`、`ipad-3.log:99` |

主页和固定用例继续可用，但“启动无未处理异常”断言明确 FAIL。[汇总](non-target-issues.json)和各轮 stdout 保留错误及堆栈。

源码线索：`DownloadController.onInit` 调用 `pathManager.allowMediaScan`；`download_path_manager.dart:48` 在 iOS 返回相对路径 `Download`，`:150` / `:157` 用该路径创建 `.nomedia`。这是后续排查位置，本次没有修复。

### 四轮返回导航时 ScrollController 已释放：保留独立 FAIL

模拟器一轮和 iPad 三轮返回导航时均记录 `A ScrollController was used after being disposed.`。堆栈经过 `ScrollController.dispose` 和 `_ModalScopeState.dispose`。原始证据：[模拟器](simulator-1-smoke.json)、[iPad 第 1 轮](ipad-1-smoke.json)、[第 2 轮](ipad-2-smoke.json)、[第 3 轮](ipad-3-smoke.json)；stdout 对应 `simulator-1.log:187`、`ipad-1.log:265`、`ipad-2.log:233`、`ipad-3.log:218`。

`back_navigation` / `settings_back` 的 PASS 仅证明页面成功返回，后续固定内容仍可打开；“返回导航时无异常”按已保存日志记为 FAIL，未追加或改写原始探针断言。业务源码中的 [GalleryPageController.onClose](/Users/fuhua/.codex/worktrees/da3d/eros_fe/lib/pages/gallery/controller/gallery_page_controller.dart:113) 也会释放滚动控制器，可作为后续排查线索；本次未证明具体根因、未修复。

### 第三轮真机 RenderFlex 底部溢出 4px：保留独立 FAIL

`ipad-3.log:151` 及 [第 3 轮 smoke JSON](ipad-3-smoke.json) 记录 `A RenderFlex overflowed by 4.0 pixels on the bottom.`。原始布局诊断指向 [gallery_item.dart:117](/Users/fuhua/.codex/worktrees/da3d/eros_fe/lib/pages/item/gallery_item.dart:117) 的 `Column`。该异常发生于内容布局阶段，页面仍可继续操作，但布局结果记为 FAIL；其余三轮未记录到同类异常。本次没有修复。

### 遮罩开启仍显示清晰多任务卡片：保留独立 FAIL

步骤：真实安全设置开关启用 → 回到固定画廊 → 打开多任务界面观察卡片 → 回到 App → 物理锁屏至少 5 秒 → 自行解锁并返回。

预期卡片内容不可辨认；用户确认“仍清晰显示内容，没有模糊”，但回到 App 正常。Dart 开关断言为 true，`ipad-3.log:2409` 原生 `isBlurredInRecentTasks : true`，锁屏恢复及真实菜单交互通过。后续应排查 [SceneDelegate.swift:5](/Users/fuhua/.codex/worktrees/da3d/eros_fe/ios/Runner/SceneDelegate.swift:5) 的遮罩添加时机、窗口和系统快照；本次未证明具体根因、未修复。

### 锁脚本退出异常：单独记录工具问题

`simulator-setup`、`ipad-2`、`ipad-3` 的退出出现 `PermissionError: [Errno 1] Operation not permitted`，位置为 `scripts/ios_lock.py:47` 的 `os.killpg(pgid, 0)`，由 `finish_group` 调用。保存 [异常索引](lock-exit-issue.json)及原始日志。后续运行成功重新取得锁，但这个观察不足以证明所有子进程退出路径均正确受保护。本次没有修改该脚本，也没有并发使用同一 Pods。

此前隔离探针通过未覆盖此次实跑暴露的退出路径。异常发生在测试完成后的进程清理阶段，不使已保存的 5A 证据失效；该退出路径需单独跟进，本次提交只记录问题。

### 首次真机安装名额问题

首次构建完成后无法启动，Flutter 等待 Xcode / Dart VM。用户在 Xcode 看到开发者 App 名额满，卸载一个 App 后重新部署成功。该尝试不计入三次回归；[原始日志](setup/device-slot-full/ipad-1.log)和 [用户说明](setup/device-slot-full/user-confirmation.json)单独保留。

### 原生崩溃与试运行

全部操作结束后，真机相关报告没有新增或变化，见 [前后清单差异](crashes/delta.json)；宿主 DiagnosticReports 中冻结源码后的 fehviewer / Runner 报告数为 0，见 [模拟器检查](crashes/simulator-check.json)。本次没有新的原生 `.ips` 可导出。Step 3 既有崩溃及报告继续保留在 [Step 3 报告](../ios-step3-20260930/REPORT.md)。本次 Dart 分享错误不直接归类为原生进程崩溃。

准备阶段和探针试运行的日志、早期补丁、采样时间问题留在 `setup/` 或 `simulator-setup*`。正式测试只使用根目录 `source-manifest.json` 对应的补丁。宿主日志等待曾将字节位置误用为字符位置，原始超时保留在 `simulator-1-driver-error.log`；同一会话随后完成实际前后台恢复，以最终 `simulator-1-lifecycle_end.json` 为准。

## 7. 文件索引与复跑入口

| 文件 | 用途 |
| --- | --- |
| [tool/fixtures/ios_step5a_data.dart](../../tool/fixtures/ios_step5a_data.dart) | 固定画廊、种子和磁力值 |
| [tool/ios_baseline_probe.dart](../../tool/ios_baseline_probe.dart) | 启动真实 App，注入数据，点击真实按钮，记录错误和生命周期；仅 iOS Debug |
| [tool/ios_baseline_driver.dart](../../tool/ios_baseline_driver.dart) | 通过当前 Debug VM 服务发出固定命令并保存 JSON |
| [run-round.py](run-round.py) | 本次宿主运行和截图的诊断记录；不是 CI 入口 |
| [source-manifest.json](source-manifest.json)、[source-changes.patch](source-changes.patch) | 固定源码及全部新增测试源码补丁 |
| [share-baseline.json](share-baseline.json) | 四次业务 FAIL 汇总 |
| [non-target-issues.json](non-target-issues.json) | 启动目录、返回导航及布局异常的逐轮索引，保留原始错误和堆栈 |
| 各轮 `.log`、JSON、PNG；`app-logs/`；`crashes/` | Flutter／原生日志、App 导出、菜单和恢复证据、崩溃清单 |

在同一 checkout 串行准备／运行，先保持本地签名配置及固定 Flutter SDK 可用：

```bash
scripts/ios_dev.sh prepare --device
scripts/ios_dev.sh run --debug -d 00008132-000278923E99001C \
  -t tool/ios_baseline_probe.dart 2>&1 | tee /private/tmp/step5a-run.log
```

看到 `STEP5A_READY` 后，另一个终端按顺序驱动：

```bash
.fvm/flutter_sdk/bin/dart \
  --packages=.fvm/flutter_sdk/packages/flutter_tools/.dart_tool/package_config.json \
  tool/ios_baseline_driver.dart /private/tmp/step5a-run.log gallery /private/tmp/gallery.json
```

同样依次执行 `torrent`、`share`、`smoke`，每次使用不同输出 JSON。`privacy enabled=true/false` 操作真实安全设置开关；`lifecycle_begin label=...` / `lifecycle_end label=...` 包围实际 OS 操作。模拟器使用同一个 Debug target，替换为上述 simulator UDID。

每次重复前在运行终端按 `q`，等待运行会话和锁释放，再重新运行。若出现第 6 节的锁脚本退出异常，应核对会话已经结束，不能把 traceback 当作正常退出通过。

## 8. 5A 通过条件核对

| 条件 | 结果 |
| --- | --- |
| 源码 commit／完整补丁、环境、设备、系统 build、Debug 固定 | 完成，冻结文件最终校验一致，生产 diff 为空 |
| 本地画廊、种子、磁力入口复用真实页面及原生分享 | 完成，不要求在线账号或实时数据 |
| 业务断言固定，修复前记录 FAIL | 完成，iPad 3/3 稳定 FAIL；模拟器亦 FAIL |
| 失败有日志、截图和源码定位 | 完成，各轮 JSON／PNG／stdout 和 App 导出已保存 |
| 小规模冒烟已有明确 PASS／FAIL | 完成，含启动、设置、内容、返回、前后台、锁屏、遮罩两状态 |
| 生命周期异常和原生崩溃单独记录 | 完成，遮罩视觉 FAIL 单独列出，无新增原生 crash report |

本次 5A 通过表示基线建立完成。目标分享、启动目录、返回导航、布局溢出、遮罩及锁退出问题均未修复。本次提交记录修复前基线及报告补正；后续锁退出处理、5B 和 Step 6 尚未执行。
