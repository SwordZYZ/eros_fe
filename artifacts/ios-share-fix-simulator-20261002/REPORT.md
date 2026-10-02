# 分享 Bug 修复：5B 模拟器与 iPad 真机验证

**分享目标用例两端均 PASS：模拟器 3/3、iPad 真机 3/3，均实际拷贝且固定磁力值一致。整体 5B 回归 FAIL：真机锁屏恢复后点击灰色种子按钮在遮罩开、关两种状态下均原生闪退，两份 `.ips` 已导出。** 5A 已有的启动目录异常、返回导航异常及遮罩开启后卡片仍清晰也继续保留 FAIL。本次更改尚未提交。

## 1. 源码、数据与环境

- 源码基点：`82251e55`，包含已提交的 5A 基线和锁退出修复。
- 生产改动仅 [torrent_dialog.dart:161](/Users/fuhua/.codex/worktrees/da3d/eros_fe/lib/pages/gallery/view/torrent_dialog.dart:161) 的磁力分享按钮：用 `Builder` 获取按钮上下文，将其 `RenderBox` 的实际位置及尺寸传入 `sharePositionOrigin`，等待真实 `Share.share` 调用。
- 测试源码为基点加 [完整生产补丁](source-changes.patch)，SHA-256 及验证脚本清单见 [源码清单](source-manifest.json)。
- 5A 探针、CLI 驱动、夹具、QR 图片均未改动。固定磁力值为 `magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567`；无需在线账号或实时网络数据。
- Xcode 27.0 / `27A266a`，Flutter 3.47.3 / Dart 3.13.3；share_plus 11.1.0；arm64 iPad Pro 11-inch M5 模拟器，iOS 27.0 / `24A434`，Debug。精确版本和设备信息见 [环境](environment.json)。
- `pubspec.lock`、`ios/Podfile.lock`、`Gemfile.lock` 未改动；原 5A 证据清单的 149 个文件均仍匹配。

5A 的原生错误为 `sharePositionOrigin: argument must be set`。当前锁定插件要求 iPad popover 的锚点非空且位于源视图范围内；本次传入点击按钮的真实矩形，没有修改原生插件、依赖版本、签名、UIScene 或其他分享入口。

## 2. CLI 验证方法

1. 经 `scripts/ios_dev.sh` 锁入口从源码构建修复后的模拟器 Debug App。
2. 连续三轮使用同一构建产物全新启动，复用冻结驱动执行 `gallery → torrent → share`。这仍点击真实页面和真实红色按钮；未伪造分享 MethodChannel。
3. 每轮分享前通过 `simctl pbcopy` 写入不同的控制标记，防止剪贴板残留造成误判。
4. 用 CLI 启动临时 XCTest 原生 UI 检查器，确认“拷贝”元素存在且可点击，实际点击并断言菜单关闭。
5. `simctl pbpaste` 读取复制结果，严格比较固定磁力值；导出 XCTest 摘要、原生辅助功能树和菜单／复制后截图。
6. 每轮输入 `q`，退出后才开始下一轮。三轮 Flutter 退出码均为 0。

临时 XCTest 项目位于独立 `/private/tmp` 目录，使用自己的锁和 DerivedData，不访问生产 Pods。生产项目构建和 Flutter 运行始终由当前 checkout 的开发锁保护。全部操作通过 CLI 执行，无 GUI 手工点击。

探针未出现 Dart 分享错误时仍返回 `NEEDS_NATIVE_OBSERVATION`，没有改为自动 PASS。本次业务 PASS 来自原生元素断言、真实复制操作及剪贴板一致性。探针保留的 `source: ...:171` 是 5A 旧行号；修复后的实际分享调用位于 [torrent_dialog.dart:173](/Users/fuhua/.codex/worktrees/da3d/eros_fe/lib/pages/gallery/view/torrent_dialog.dart:173)。

## 3. 分享重复结果

| 轮次 | 菜单及拷贝 | 剪贴板 | 证据 |
| --- | --- | --- | --- |
| 模拟器 1 | **PASS**，可点击且菜单关闭 | 固定磁力值完全一致 | [结果](simulator-1-result.json)、[原生测试](simulator-1-native-summary.json)、[菜单截图](simulator-1-share.png) |
| 模拟器 2 | **PASS** | 固定磁力值完全一致 | [结果](simulator-2-result.json)、[原生测试](simulator-2-native-summary.json)、[菜单截图](simulator-2-share.png) |
| 模拟器 3 | **PASS** | 固定磁力值完全一致 | [结果](simulator-3-result.json)、[原生测试](simulator-3-native-summary.json)、[菜单截图](simulator-3-share.png) |

每轮原生 XCTest 均为 1 项通过、0 项失败。汇总见 [三轮结果](share-results.json)。`simulator-N-native-attachments/manifest.json` 索引原生菜单、复制后截图和辅助功能树。

### 检查器试运行的定位失败

第一次检查器按 Button 查找“拷贝”，但 iOS 27 的原生分享菜单将它标为 Cell，导致等待失败。原辅助功能树已显示真实 Popover、`ShareSheet.RemoteContainerView` 和“拷贝”动作，但当时未完成复制验证，未计入正式 PASS。

仅将检查器定位方式改为按标签查找原生元素，生产修复保持冻结，随后重新完成三轮。失败摘要、旧检查器、菜单截图、原始日志和导出附件保留在 [试运行目录](setup/selector-attempt1/simulator-1-native-summary.json)。

## 4. 模拟器冒烟与 5A 比较

另进行一次从同一构建产物启动的模拟器冒烟：固定内容和种子菜单 → 返回导航 → 真实设置 → 返回并重新打开固定内容 → CLI 切换到系统设置并返回 App → 重新打开、关闭真实种子菜单。

| 用例 | 5A | 本次模拟器 |
| --- | --- | --- |
| 冷启动进入主页、无在线账号 | PASS | **PASS** |
| 打开固定内容、种子菜单 | PASS | **PASS** |
| 进入设置、返回导航、重新打开固定内容 | PASS，仅导航结果 | **PASS，仅导航结果** |
| 实际前后台恢复、无恢复期异常、菜单交互恢复 | PASS | **PASS** |
| 系统分享菜单出现且可用 | FAIL | **PASS，3/3，实际拷贝** |
| 启动无未处理异常 | FAIL，`FileSystemException / errno 30` | **仍 FAIL，同一目录异常** |
| 返回导航时无异常 | FAIL，已释放的 `ScrollController` | **仍 FAIL，同一异常** |

导航 PASS 仍只说明成功返回；上述两项既有错误没有被隐藏或视为修复。此次模拟器未记录 `RenderFlex` 溢出。隐私遮罩、多任务卡片和实际锁屏解锁留待真机验证，不据模拟器结果判定。

结构化结果见 [冒烟记录](simulator-smoke-result.json)、[比较表及完整异常](baseline-comparison.json)、[恢复截图](simulator-smoke-restored.png)。模拟器阶段结束时检查源码冻结后的宿主和该模拟器相关原生崩溃目录，未发现新的 Runner／fehviewer `.ips`，见 [崩溃检查](native-crash-check.json)。

## 5. 构建和静态检查

- 生产模拟器构建退出 0；临时原生检查器构建退出 0。
- 目标 Dart 文件分析没有 error 或 warning，但保留原有 7 条 info 级样式／弃用提示。默认分析因此返回 1；`--no-fatal-infos` 返回 0，error／warning 仍为致命。两次退出码和提示完整保存在 [静态检查](static-check.json)。
- `git diff --check` 通过；唯一生产差异为目标磁力按钮。真机分享三轮通过，但锁屏后交互出现原生崩溃，整体 5B 回归未通过，详见第 7 节。

## 6. 文件索引及复跑入口

| 文件 | 用途 |
| --- | --- |
| [run-simulator-check.py](run-simulator-check.py) | CLI 冷启动、冻结驱动、三轮原生拷贝及精确剪贴板比较 |
| [ShareMenuChecks.swift](ShareMenuChecks.swift)、[generate-ui-check.rb](generate-ui-check.rb) | 临时原生检查器源码及项目生成器 |
| [run-smoke-cli.py](run-smoke-cli.py) | 使用原 5A 驱动比较模拟器冒烟 |
| [source-manifest.json](source-manifest.json)、[source-changes.patch](source-changes.patch) | 基点、完整修复补丁、固定数据及源文件哈希 |
| [evidence-sha256.json](evidence-sha256.json) | 全部本地证据校验值，不含清单自身及 Python 缓存 |

```bash
# 必须先构建修复源码；不能直接验证旧的本地 App 产物
scripts/ios_dev.sh build ios --debug --simulator --no-codesign \
  -t tool/ios_baseline_probe.dart
```

三轮检查需先按 `generate-ui-check.rb` 生成独立项目并执行 `build-for-testing`；`harness-path.txt` 指向本次临时目录。`run-simulator-check.py` 的结果 bundle 路径必须不存在，复跑使用新的临时目录及独立证据副本，避免覆盖本次冻结结果。

各轮 `.log` 沿用仓库忽略规则保留本地；可提交的 JSON、PNG、原生附件和哈希清单已保存关键断言和错误。原始 `.xcresult` 在临时目录保留，摘要及附件已导出到本目录。

## 7. iPad 真机验证

**常规冷启动的分享目标用例 PASS，3/3；真机生命周期回归 FAIL，整体 5B 未通过。** 用户确认三轮原生菜单均可实际拷贝，复制内容与固定磁力值逐字一致，菜单关闭后 App 正常。锁屏解锁后的种子入口在遮罩开启、关闭两种状态下均出现原生闪退，不能将三轮分享成功解释为全部回归通过。

### 7.1 同一源码、数据和 CLI 流程

- 设备为 iPad Pro 11-inch M4 / `iPad16,3`，iPadOS 27.0 / `24A437`，USB，Debug。使用同一 `82251e55` 基点和冻结分享补丁；5A 驱动、夹具、依赖锁文件保持原值。
- 经 `scripts/ios_dev.sh build ios --debug -t tool/ios_baseline_probe.dart` 从源码构建签名包，退出 0。固定开发 Bundle ID 为 `com.fuhua.erosfe.step5a`。后续三轮和冒烟均使用该构建产物，没有重新修改代码。
- 每轮经同一开发锁启动 `run --debug -d 00008132-000278923E99001C -t tool/ios_baseline_probe.dart --use-application-binary=build/ios/iphoneos/fehviewer.app`，冷启动后由原 5A 驱动执行 `gallery → torrent → share`，实际点击真实页面与红色按钮。
- 模拟器通过 XCTest 点击原生“拷贝”，再用 `simctl` 读取剪贴板；真机由用户点击原生菜单并直接粘贴复制值。真机未写入模拟器使用的剪贴板控制标记，复制值证据来源明确为人工反馈。
- CLI `devicectl` 截图未显示原生系统分享菜单，截图本身不作为菜单出现的断言。真机原生菜单可用性来自用户实际操作及粘贴结果；Dart 探针仍保留 `NEEDS_NATIVE_OBSERVATION`，没有改写其原始断言。
- 全部构建、部署、固定页面准备、前后台切换、截图和日志导出走 CLI；系统分享操作、多任务卡片观察和物理锁屏由用户完成，未使用 computer use。

构建及安装信息见 [真机构建清单](device/build-manifest.json)、[设备信息](device/device-before.json)、[安装信息](device/installed-app.json)。构建二进制 UUID 为 `784C2B55-2BC5-3DCC-B98C-675604CCB4E7`，见 [UUID](device/binary-uuid.txt)，与两份新原生崩溃报告的 `slice_uuid` 一致。

### 7.2 三轮目标分享结果

| 轮次 | 原生菜单与实际拷贝 | 用户粘贴复制值 | 菜单关闭后 App | 证据 |
| --- | --- | --- | --- | --- |
| iPad 1 | **PASS** | 与固定磁力值完全一致 | 正常 | [人工结果](device/ipad-1-manual-result.json)、[探针](device/ipad-1-share.json)、[App 导出](device/ipad-1-app-events.json) |
| iPad 2 | **PASS** | 与固定磁力值完全一致 | 正常 | [人工结果](device/ipad-2-manual-result.json)、[探针](device/ipad-2-share.json)、[App 导出](device/ipad-2-app-events.json) |
| iPad 3 | **PASS** | 与固定磁力值完全一致 | 正常 | [人工结果](device/ipad-3-manual-result.json)、[探针](device/ipad-3-share.json)、[App 导出](device/ipad-3-app-events.json) |

三轮完整反馈、来源及退出码见 [真机分享汇总](device/share-results.json)。每轮退出后才启动下一轮，Flutter 正常退出码均为 0；三轮分享调用未记录 `sharePositionOrigin` 错误。

### 7.3 冒烟与 5A 对照

三轮之后独立冷启动同一产物完成冒烟：固定画廊、种子菜单、返回主页、真实设置、返回固定内容，再通过 CLI 启动系统设置并返回测试 App。随后测试两种遮罩状态、多任务卡片和物理锁屏至少 5 秒后的恢复及种子交互。

| 用例 | 5A 真机基线 | 本次真机 |
| --- | --- | --- |
| 冷启动、无线上账号、打开固定内容和种子菜单 | PASS | **PASS** |
| 设置、返回导航、重新打开固定内容 | PASS，仅导航结果 | **PASS，仅导航结果** |
| 实际前后台恢复、恢复期无异常、真实种子菜单重新打开关闭 | PASS | **PASS** |
| 系统分享菜单出现且实际可用 | FAIL | **PASS，常规冷启动 3/3，实际拷贝** |
| 启动无未处理异常 | FAIL，`PathAccessException / errno 1` | **仍 FAIL，同一错误，六次启动均记录** |
| 返回导航时无异常 | FAIL，已释放的 `ScrollController` | **仍 FAIL，独立冒烟中记录** |
| 遮罩关闭的多任务卡片 | PASS，清晰 | **PASS，清晰** |
| 遮罩开启的多任务卡片 | FAIL，仍清晰 | **仍 FAIL，仍清晰，没有模糊** |
| 两种状态锁屏解锁后最初回到 App | PASS | **PASS，用户看到正常内容，App 导出记录 resumed** |
| 遮罩开启后锁屏恢复的种子交互及无原生崩溃 | PASS | **FAIL，点击灰色种子按钮原生闪退** |
| 遮罩关闭后锁屏恢复的种子交互及无原生崩溃 | PASS | **FAIL，同样原生闪退** |
| 4px RenderFlex 溢出 | 5A 第三轮记录 FAIL | **本次未复现，未修复，不作普遍 PASS 声明** |

导航 PASS 仅表示成功返回，不代表没有异常。恢复内容可见也不等于恢复后交互可用；两种状态均在后续灰色种子按钮操作中失败。结构化比较及完整异常见 [真机比较表](device/baseline-comparison.json)。

遮罩关闭首次尝试中，用户只确认卡片清晰和回到 App 正常；Flutter 连接断开使自动菜单交互无法执行，见 [第一次关闭状态](device/privacy-off-manual.json)、[导出分析](device/lock-off-export-analysis.json)。之后在同一构建产物的新进程补测实际菜单交互，结果为原生闪退，见 [关闭状态补测](device/privacy-off-retry-manual.json)。最终对照采用补测的 FAIL，未用首次“App 正常”覆盖它。

### 7.4 新增原生闪退：两份报告均已导出

固定步骤：真实安全设置确认遮罩状态 → 回到固定画廊 → 观察多任务卡片 → 回到 App → 短按电源键锁屏至少 5 秒 → 正常解锁返回 → 点击画廊中间灰色种子按钮。用户分别在开启和关闭状态反馈“种子及分享菜单不可用，点击灰色磁铁闪退”。

| 状态 | 系统报告时间（北京时间） | 原生结果 | 完整报告 |
| --- | --- | --- | --- |
| 遮罩开启 | 2026-10-02 22:24:40 | `EXC_BAD_ACCESS / SIGBUS`，主线程，Bus error 10 | [fehviewer-2026-10-02-222440.ips](device/fehviewer-2026-10-02-222440.ips) |
| 遮罩关闭 | 2026-10-02 22:29:35 | `EXC_BAD_ACCESS / SIGBUS`，主线程，Bus error 10 | [fehviewer-2026-10-02-222935.ips](device/fehviewer-2026-10-02-222935.ips) |

两份报告均属于 `com.fuhua.erosfe.step5a`，二进制 UUID 与本次构建一致。App 事件在两次锁屏后均记录 `paused → resumed`；随后原生崩溃，没有相应 Dart 异常。不能以 Dart 事件中没有 error 判定“无异常”。

[前后崩溃清单差异](device/crashes-delta.json)为 2 份新增报告；[崩溃摘要](device/crash-summaries.json)保存退出原因、线程帧和映像索引。崩溃线程顶部为未命名映像，现有报告未定位业务根因。源码入口线索为 [灰色种子按钮](/Users/fuhua/.codex/worktrees/da3d/eros_fe/lib/pages/gallery/view/sliver/slivers.dart:63) 调用 [showTorrentDialog](/Users/fuhua/.codex/worktrees/da3d/eros_fe/lib/pages/gallery/view/torrent_dialog.dart:190)。该操作尚未完成红色分享按钮调用，现有验证不足以归因分享补丁或确定其他具体原因。本次保留失败并停止扩大修复范围。

### 7.5 调试断连与开发锁遗留进程

首次关闭遮罩的物理锁屏阶段，Flutter 输出 `Lost connection to device`；宿主驱动后续调用报 `SocketException / errno 61`。App 仍运行，事件导出记录解锁后 `resumed`。这属于宿主连接失败，不能据此直接认定 App 已崩溃。

当时 Flutter 运行命令已经返回 0，但一个失去父进程的 `devicectl --console`（PID `21200`，PPID `1`，PGID `21200`）仍继承开发锁文件描述符。重新附加等待锁，保存的 `lsof` 和进程信息确认该残留。仅对本轮已识别的孤立控制台发送 `SIGTERM`，未删除锁文件或绕过锁；控制台结束也停止了原 Debug App，重新附加没有成功，取消后用同一产物的新进程继续测试。

证据见 [断连记录](device/lock-off-debug-disconnect.json)、[锁文件持有者](device/lock-after-disconnect.log)、[重新附加结果](device/reattach-attempt-result.json)。这暴露了独立进程组继承描述符的清理路径，原 `82251e55` 的 EPERM 修复没有覆盖此观察。本次没有修改锁脚本。最终 [锁探针](device/final-lock-check.exit)返回 0，表示本次测试结束时可正常获取锁，不能作为该遗留路径已修复的结论。

运行命令退出 0 也不能覆盖原生崩溃结果：两次锁屏后交互的业务和原生断言均明确 FAIL。

### 7.6 真机文件索引

| 文件 | 用途 |
| --- | --- |
| [verification-status.json](device/verification-status.json)、[baseline-comparison.json](device/baseline-comparison.json) | 最终范围、分享 PASS、完整回归 FAIL、逐项 5A 对照 |
| [drive.py](device/drive.py) | 宿主 CLI 包装器，调用未修改的 5A 驱动并导出截图／App 事件 |
| [share-results.json](device/share-results.json)、`ipad-N-manual-result.json` | 三轮实际原生拷贝、用户原话、复制值精确比较 |
| `ipad-N-gallery/torrent/share/snapshot.json`、`ipad-N-app-events.json` | 各轮固定页面、真实红色按钮、原始探针断言和异常 |
| `ipad-smoke-*.json`、[ipad-smoke-app-events.json](device/ipad-smoke-app-events.json) | 导航、设置、前后台与第一次物理锁屏记录 |
| [privacy-on-manual.json](device/privacy-on-manual.json)、[privacy-off-retry-manual.json](device/privacy-off-retry-manual.json) | 两种状态的卡片观察、物理锁屏及实际交互失败 |
| `ipad-privacy-on/off-retry-*.json`、同名 `.log` | 开关确认、锁屏生命周期、App 导出和原始 stdout |
| [crashes-delta.json](device/crashes-delta.json)、[crash-summaries.json](device/crash-summaries.json)、两份 `.ips` | 新增原生崩溃及完整报告 |
| [native-app-log-files.json](device/native-app-log-files.json) | `Documents/log` 目录检查成功，无文件；Flutter 日志和 App 事件已另存 |
| [source-manifest.json](source-manifest.json)、[evidence-sha256.json](evidence-sha256.json) | 同一源码／固定数据／锁文件证明及所有证据哈希 |

真机数据及日志全部追加到本模拟器修复报告目录的 `device/`。原模拟器逐轮原始证据及原 5A 的 149 个证据文件未改写，完整证据清单已重新生成。`.log` 按仓库规则保留本地；JSON、截图和 `.ips` 保存关键证据。

**本次真机验证已完成留证：分享目标 3/3 PASS，生命周期回归 FAIL。生产修复保持模拟器验证时的唯一磁力锚点改动，更改尚未提交。**
