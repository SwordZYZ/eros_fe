# iOS / iPadOS 本地开发

## 固定基线与入口

- Xcode **27.2**，模拟器使用 **arm64 iOS 27.2**，真机验收使用 **iPadOS 27.2**。App 最低部署目标为 **iOS 15.6**。
- Flutter **3.47.3** / Dart **3.13.3**。项目使用 CocoaPods **1.16.2**，由 `Gemfile.lock` 固定。
- Xcode 和模拟器的版本配置见 [`tool/ios_toolchain.json`](../tool/ios_toolchain.json)。
- 所有开发任务从仓库根目录调用 `scripts/ios_dev.sh`。`--help` 查看命令；输出默认写到 `artifacts/ios-dev/`，可用 `IOS_LOG_DIR` 指定独立目录。
- 同一 checkout 的准备、安装、构建、运行、冒烟和日志采集共用项目锁。不同 SDK 的构建按顺序执行。详情见 [构建锁](ios-build-lock.md)。

## 新 checkout 的首次准备

1. 安装 Xcode 27.2，选择其 Developer 目录，然后按下文安装 **iOS 27.2 arm64 Simulator runtime**。
2. 安装 FVM 和 Ruby Bundler。在项目中运行 `fvm install 3.47.3` 和 `fvm use 3.47.3`，或将 `IOS_FLUTTER_BIN` 指向已经安装的 **3.47.3** Flutter 可执行文件。
3. 执行公开配置准备。它会从 `Local.xcconfig.example` 建立被忽略的本地签名配置，按锁安装 Dart / Ruby / Pods，检查配置并生成代码。公开 `config.dart` 和禁用的 Firebase 不需要维护者密钥；不要将加密 Firebase plist 加入 Runner 的 resources。

VS Code 通过 `.fvm/flutter_sdk` 使用 Flutter 自带的 Dart SDK。若编辑器仍在运行旧版 Dart 分析服务，先退出 VS Code，再执行 FVM 配置和模拟器准备，完成后重新打开项目。

```bash
scripts/ios_dev.sh prepare --simulator
scripts/ios_dev.sh check
scripts/ios_dev.sh build ios --simulator --debug
scripts/ios_dev.sh smoke --simulator auto
```

`smoke --simulator auto` 和 `logs simulator auto` 共用选择器。`auto` 创建或复用名为 `Eros-FE-<checkout 路径哈希>` 的专用 iPad 模拟器，严格使用 iOS 27.2 arm64 runtime，然后启动并等待 boot 完成。冒烟命令也可使用该 runtime 下的模拟器 UDID。不同 checkout 使用不同模拟器，避免测试状态混用。

准备阶段不使用 `pub upgrade` 或 `pod update`。日常安装继续执行 `pub get --enforce-lockfile` 和 `pod install --deployment`；`scripts/ios_dev.sh pods` 可单独重复安装。只有明确变更依赖时，才重新建立并审查锁文件。

## 手动管理模拟器

1. 在 **Xcode → Settings… → Components** 管理系统镜像。退役 27.0 时找到 **iOS 27.0**，点击该条目旁边的 ⓘ，再选 **Delete**。使用 27.0 的模拟设备会失去所需的 runtime。 [Apple 组件管理说明](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)
2. 同页查看 **iOS 27.2**。如果显示 **Get**，点它直接安装。若主列表显示的是更新版本，用 **Other Installed Platforms → Add Platforms (+)** 选中 **iOS 27.2**，再点 **Download & Install**。已安装的 27.2 可直接使用。 [Apple 运行时安装说明](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)
3. 在 **Xcode → Open Developer Tool → Device Hub** 管理单台模拟设备。如果 27.2 下还没有 iPad，点 **+**，选择 **iPad Pro 11-inch (M5)** 和 **iOS 27.2**，再点 **Create**。如需清理某台旧设备及其本地 App 数据，确认它的系统版本后，在该设备上按住 Control 点击并选 **Remove**。 [Apple Device Hub 说明](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub)

下列命令只读。预期运行时标识为 `com.apple.CoreSimulator.SimRuntime.iOS-27-2`，应显示可用并支持 `arm64`。

```bash
xcodebuild -version
xcrun simctl list runtimes
python3 tool/ios_simulator.py --check
```

## 真机 Debug

先用 USB 连接并解锁运行 iPadOS 27.2 的 iPad，启用 Developer Mode，在 Xcode 完成设备准备和 Apple 开发账号登录。签名构建使用开发者自己的 Apple 开发签名。

编辑本地 `ios/Flutter/Local.xcconfig`：

```xcconfig
IOS_DEVELOPMENT_BUNDLE_IDENTIFIER = com.yourteam.erosfe.dev
IOS_DEVELOPMENT_TEAM = YOURTEAMID
```

Team ID 为 10 位；Bundle ID 使用自己的开发标识。签名配置不提交。准备入口在构建前拒绝样例 Bundle ID 或无效 Team ID。

```bash
export FLUTTER_LLDB_DEBUGGING=true # 本命令环境选择 LLDB / devicectl，避免依赖 Xcode GUI 自动化。
scripts/ios_dev.sh prepare --device &&
  scripts/ios_dev.sh check &&
  scripts/ios_dev.sh run --debug -d "$IPAD_UDID"
```

`run` 会编译、签名、安装、启动并连接 Dart 调试器，保持标准输入可用。使用 Flutter 的 `r` 热重载、`R` 热重启、`q` 退出或 `d` detach。整个会话持续持锁；退出或调试断连后，先清理受监督的构建进程，再释放锁。

锁描述符仅由监督进程持有，不传给 Flutter / Xcode / devicectl。嵌套入口通过带随机令牌的本地 UNIX socket 向当前监督进程校验；监督进程结束后旧令牌失效。即使 `devicectl --console` 成为独立进程组的孤立进程，也不能继续占用开发锁。已有旧版本遗留的控制台需按 PID 和命令确认后结束，不能删除锁文件来绕过占用。

默认遇到占用输出等待提示和持有者 PID；需要立即拒绝时：

```bash
IOS_LOCK_WAIT=0 scripts/ios_dev.sh build ios --simulator --debug
```

忙时返回 `75`，未启动实际命令。普通失败退出码保留；INT / TERM / HUP 中断返回 `128 + 信号编号`。

### 保留开发 App 并覆盖安装

在 iPad 上长期保留一个用于手动验收的开发 App。各 checkout 在本地 `Local.xcconfig` 中复用它的开发 Bundle ID 和签名团队，日用 App 使用自己的 Bundle ID。签名的 `application-identifier` 一致时，覆盖安装通常保留 App 容器，账号和布局能否继续使用也取决于应用的数据迁移。同一台 iPad 上共用该标识的任务应串行安装与验收，各 checkout 的构建锁只保护自己的目录。 [Apple 的更新测试说明](https://developer.apple.com/documentation/xcode/testing-a-release-build) · [Apple 的签名故障排查](https://developer.apple.com/library/archive/technotes/tn2319/_index.html)

| 场景 | 操作 |
| --- | --- |
| 同一个构建再测一轮 | 已安装的签名 Profile 包可按下节的 `devicectl` 命令直接启动。需要从新进程开始时，确认上一轮证据已保存，再给启动命令加 `--terminate-existing`。 |
| 同一个 Debug 会话修改 Dart | 支持热重载的改动用 `r`，需要重新执行 Dart 初始化时用 `R`。Swift、插件或构建配置变更后，结束调试会话并重新构建与安装。 [Flutter 热重载说明](https://docs.flutter.dev/tools/hot-reload) |
| 换分支或开始正式验收 | 在目标 checkout 先跑 `prepare --device`，再按上方流程运行 Debug，或按下节重建签名 Profile 包并覆盖安装。`run` 使用 `--no-pub`，准备步骤负责同步当前分支的锁定依赖和 Pods。新构建仍需签名，有效的签名配置可复用。记录本轮源码 commit 和构建模式。 |

结束日常 Debug 时，用 `q` 停止进程并保留安装。需要全新安装或排除旧数据干扰时，优先使用单独的测试 Bundle ID。覆盖失败时保留旧 App 和安装错误，先核对签名及描述文件。若确实需要删除已有开发 App，先确认可以清除其数据，并保存当轮证据。 [Apple 的开发签名说明](https://developer.apple.com/help/account/provisioning-profiles/create-a-development-provisioning-profile/)

## CLI 真机锁屏回归

构建、安装、启动和取证优先使用 `ios_dev.sh`、`simctl` 和 `devicectl`。平时用 `flutter run` 做前台 Debug 和热重载。锁屏与解锁由使用者在 iPad 上操作，界面自动化可用于观察自动化命令覆盖不到的场景。开发链路验收只需确认启动、原进程恢复和证据采集。刷新、分享及复制的结果由对应业务用例单独验收。 [真机对照摘要](ios-lockscreen-validation.md)

### 构建与启动

先通过模拟器 `scripts/ios_dev.sh ci`，再在同一源码和固定工具链下为手动验收的开发 Bundle ID 构建签名 Profile 包。下面的 `IPAD_UDID` 是通过 USB 连接的 iPad，`DEVELOPMENT_BUNDLE_ID` 与本地签名配置一致，`EVIDENCE_DIR` 是本地取证目录。普通 Profile 包使用默认入口，可以直接做手动锁屏验证。

```bash
APP_PATH="$PWD/build/ios/iphoneos/fehviewer.app"
scripts/ios_dev.sh prepare --device &&
  scripts/ios_dev.sh build ios --profile &&
  codesign --verify --strict "$APP_PATH" &&
  mkdir -p "$EVIDENCE_DIR" &&
  python3 scripts/ios_lock.py -- xcrun devicectl device install app \
    --device "$IPAD_UDID" --timeout 60 "$APP_PATH" &&
  xcrun devicectl device process launch --device "$IPAD_UDID" --timeout 20 \
    --json-output "$EVIDENCE_DIR/launch.json" "$DEVELOPMENT_BUNDLE_ID"
```

公开 checkout 中的 `tool/ios_baseline_probe.dart` 仅支持 Debug。上面的普通 Profile 流程可用于手动锁屏验证。如果已经有支持 Profile 探针的测试 checkout，可沿用 Flutter **3.47.3** 和 Dart **3.13.3**，用 `scripts/ios_dev.sh build ios --profile --target tool/ios_baseline_probe.dart --dart-define=IOS_REFRESH_PROBE=true` 构建专项包。其安装和直接启动命令与上面相同。记录探针源码与构建参数。仅在需要连接探针驱动时设置 VM Service 端口和 USB 转发，确认 `STEP5A_READY` 后再连接。VM Service 认证 URL 仅写入本地日志。

Debug/JIT 专项可以用 `devicectl device process launch --start-stopped` 暂停启动，再由独立 LLDB 附加。使用构建该包的 checkout 生成的 `ios/Flutter/ephemeral/flutter_lldbinit`。Flutter 3.47.5 的专项实验曾通过手动继续 JIT 断点保住原进程，解锁后 VM Service 仍不可达。Xcode GUI 启动的同条件表现尚待对照。

### 锁屏前后取证

1. 锁屏前记录构建模式、测试 Bundle ID、App PID 和已有崩溃报告清单。使用者锁屏至少 5 秒，解锁后确认 App 回到原场景并能响应。
2. 锁屏前和解锁后分别设置 `SNAPSHOT_DIR` 为各自的目录，执行下列只读命令。检查 iPad 的 USB 可达性、候选 App 路径及 PID。若运行带探针的包，检查落盘事件是否出现 `paused` 和 `resumed`。使用 LLDB 或 VM Service 的轮次分别记录附加状态和重新连接结果，未使用的项目记为「不适用」。
3. 若出现断连、退出或界面不响应，先保存宿主输出、设备快照、探针事件和新增 `.ips`，再重启或重装。记录宿主是否发出了终止命令，分别判定调试会话中断、原生崩溃以及 App 恢复后的业务结果。

```bash
mkdir -p "$SNAPSHOT_DIR"
xcrun devicectl device info details --device "$IPAD_UDID" --timeout 15 \
  --json-output "$SNAPSHOT_DIR/device.json"
xcrun devicectl device info processes --device "$IPAD_UDID" --search fehviewer \
  --timeout 15 --json-output "$SNAPSHOT_DIR/processes.json"
xcrun devicectl device info files --device "$IPAD_UDID" \
  --domain-type systemCrashLogs --search fehviewer \
  --timeout 15 --json-output "$SNAPSHOT_DIR/crash-files.json"
```

带探针的包把事件写到 `Documents/step5a-events.json`，可在 VM Service 断开时直接通过 CoreDevice 读取。在改动 App 状态前执行以下命令，并检查复制退出码和 JSON 内容。

```bash
xcrun devicectl device copy from --device "$IPAD_UDID" \
  --domain-type appDataContainer --domain-identifier "$DEVELOPMENT_BUNDLE_ID" \
  --source Documents/step5a-events.json --destination "$SNAPSHOT_DIR/step5a-events.json" \
  --timeout 20 --json-output "$SNAPSHOT_DIR/probe-copy.json"
python3 -m json.tool "$SNAPSHOT_DIR/step5a-events.json" > /dev/null
```

`scripts/ios_dev.sh logs device` 可实际复制匹配测试 Bundle ID 的 `.ips`，并将各项结果写入 `collection.json`。它也采集 `Documents/log`。在重启或重装前确认相应采集项的退出码和产物。原始设备标识、认证 URL、日志和崩溃报告保存在本地取证目录，提交中只加入脱敏摘要。

## 冒烟范围与复现驱动

`integration_test/ios_smoke_test.dart` 使用官方 `integration_test`，从真实 `lib/main.dart` 启动 App，检查无线上账号、首页、真实样式设置页面与返回导航。它不等待线上账号或实时 API 数据；Flutter 异常和测试断言失败均导致非零退出。

真机冒烟使用专门的 Bundle ID 和未登录的测试数据。这个标识应与日用 App 和保留的手动验收 App 都不同，并在单独的 checkout 配置。Flutter 集成测试默认会在结束后卸载测试包。即使传入 `--no-uninstall`，Flutter 仍会覆盖安装集成测试包。

```bash
scripts/ios_dev.sh prepare --device &&
  scripts/ios_dev.sh smoke --device "$IPAD_UDID"
```

最小冒烟不替代第五步的固定内容、分享、前后台、遮罩及物理锁屏回归。已有失败须保留，不能用基础冒烟通过覆盖它们。扩展复现仍可复用现有 Debug 入口和驱动：

```bash
scripts/ios_dev.sh run --debug -d "$IPAD_UDID" --target tool/ios_baseline_probe.dart
# 在另一终端调用已固定 SDK 的 Dart；FLUTTER_SDK 为 SDK 目录。
"$FLUTTER_SDK/bin/dart" \
  --packages="$FLUTTER_SDK/packages/flutter_tools/.dart_tool/package_config.json" \
  tool/ios_baseline_driver.dart "$RUN_LOG" gallery "$RESULT_JSON"
```

驱动的 `snapshot` / `gallery` / `torrent` / `smoke` / `privacy` / `lifecycle_begin` / `lifecycle_end` 可复用第五步固定数据。它的历史结果可能包含 FAIL，阅读完整 JSON 和原生崩溃结果。系统分享菜单、实际复制／快捷指令、物理锁屏和遮罩视觉观察由使用者在 iPad 上手动完成，记录观察与原话；命令行不能代替这些验收。

## 日志与可追溯记录

每个入口任务保存完整合并 stdout / stderr 和 JSON 清单，包含起止时间、退出码、源码 commit、工作区状态、源码与三个锁文件的 SHA-256，以及命令和目标 UDID。未提交源码由工作区状态与源码哈希区分，不能仅引用基点 commit。日志不会等待孤立控制台继承的输出管道 EOF，主命令退出后即完成记录。

```bash
scripts/ios_dev.sh logs simulator auto com.example.erosfe.dev
scripts/ios_dev.sh logs device "$IPAD_UDID" "$DEVELOPMENT_BUNDLE_ID"
```

模拟器采集 runtime / 设备信息、最近 10 分钟 App 原生系统日志、截图、App 日志目录和匹配 Bundle ID 的 `.ips`。真机采集设备详细信息（机型、系统版本及 build）、App 日志目录和匹配 Bundle ID 的系统崩溃报告。`collection.json` 逐项记录采集退出码和缺失状态；采集完成不等于业务验收通过。App 日志目录为空时，以 run / smoke 控制台日志为主要来源。若 App 尚未安装或设备不可访问，原始采集失败保留在清单内。

冒烟卸载测试包后，如需验证应用容器日志采集，可在原冒烟标识下用 `run --debug` 安装普通 Debug App，启动后按 `d` 解除调试连接，再运行 `logs device` 并查看 `collection.json` 中 `app-files` 和 `app-log` 的退出码。锁屏断连或崩溃的现场按上节先取证，再更改安装或进程状态。

验收记录至少填写：源码 commit 与补丁／哈希、机型及 UDID、系统版本与 build、Debug 模式、Bundle ID、实际步骤、结果与日志索引。原生崩溃保留 `.ips`，断连保留宿主连接日志，二者分别判定。

## 同一入口的 CI

```bash
scripts/ios_dev.sh ci
```

此命令串行执行宿主锁回归、公开配置准备、环境检查、生产入口模拟器 Debug 构建、集成冒烟启动及锁文件稳定性检查。失败立即停止，原退出码上抛；CI 没有 `continue-on-error`。

`.github/workflows/ios-development.yml` 使用 **`xcode-27` arm64 runner**，显式选择 `/Applications/Xcode_27.2.app/Contents/Developer`、Flutter 3.47.3 和缓存 Ruby 3.4.12。镜像预装 iOS 27.2 模拟器。每次运行都检查宿主架构、Xcode 版本，以及 iOS 27.2 runtime 的标识、可用状态和 arm64 支持。 [runner 软件清单](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)

CI 在 PR、相关 master 推送或手动 dispatch 时运行，使用公开配置及独立 checkout / Pods；没有解密私钥、开发签名或发布动作。诊断与上传步骤使用 `always()`，失败时也保留命令日志、断言、清单及可用的 `.xcresult`，保留期 14 天。

可主动验证冒烟失败会返回非零（此命令预期 FAIL）：

```bash
scripts/ios_dev.sh smoke --simulator auto --dart-define=IOS_SMOKE_FORCE_FAILURE=true
```

`IOS_SMOKE_FORCE_FAILURE` 仅用于测试末尾故意失败的断言；不改变生产入口。

## 27.2 基线验收（2026-11-18）

本地验收使用 macOS 27.2、Xcode 27.2（`27B52`）、Flutter 3.47.3 和 CocoaPods 1.16.2。模拟器和真机在独立 checkout 上使用提交中的依赖锁文件，验收前后的三个锁文件 SHA-256 一致。

| 环境 | 验收结果 |
| --- | --- |
| iPad Pro 11-inch (M5) 模拟器，arm64 iOS 27.2（`24B8117`） | `scripts/ios_dev.sh ci` 通过，覆盖 14 个宿主测试、依赖准备、环境检查、Debug 构建和集成冒烟。`logs simulator auto` 采集了运行时、设备信息、原生系统日志和截图。冒烟退出后应用容器已不可用。 |
| iPad Pro 11-inch (M4) 真机，iPadOS 27.2（`24B119`） | USB 下 Debug 启动、实际 Dart 热重载和集成冒烟通过。恢复普通 Debug App 后，设备信息、应用日志目录和崩溃报告查询均成功。应用日志目录为空，本次控制台日志由 `run` 和 `smoke` 保留。 |
| GitHub Actions | 公开 PR 分支上的 27.2 开发基线通过了构建、冒烟和诊断采集。 [首轮远端实跑](https://github.com/SwordZYZ/eros_fe/actions/runs/44298507969) |

首次无线调试在发现 Dart VM 时收到 mDNS `No route to host`，改用 USB 后通过。模拟器在镜像重新安装和挂载期间有两次未完成的尝试，挂载完成后同一入口重跑通过。

## 并行与后续修复

同一 checkout 串行使用这些入口。Xcode GUI、VS Code 直接 launch 或裸 `flutter` / `xcodebuild` 不会自动遵守此锁。需双端同时开发时使用独立 worktree，各自安装 Pods、生成配置、`.dart_tool`、DerivedData 和输出；可以共享下载缓存，不能共享被 helper 改写的 Pods 文件。旧 IPA 脚本的共享导出位置另需隔离。

日常工作按“记录环境与复现 → 修改 → 模拟器自动冒烟 → 真机目标步骤 → 导出日志／崩溃报告 → review 与提交”推进。构建／自动测试结果和手动观察分别保留，已有失败不改写为通过。
