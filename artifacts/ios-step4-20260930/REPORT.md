# 第四步：iOS 27.0 arm64 模拟器验收

## 结论

**通过第四步验收。** 使用同一份源码、同一份 Pods 安装和同一组固定输入，依次完成“模拟器 → iPad → 模拟器”的 Debug 构建、安装、启动和功能验证。三轮各七项检查全部成功，共 21 项。

本次基于第三步提交 `a95759a772a715f9c3ff38b54613d045a280e2ae`，沿用其中的 UIScene 适配和本地签名配置。验收通过后，用户于 2026-10-01 授权将第四步源码、固定输入和验收记录提交到当前 worktree。

## 环境与运行记录

| 项目 | 实际值 |
| --- | --- |
| 日期、时区 | 2026-09-30，Asia/Shanghai |
| Xcode / SDK | Xcode 27.0，build `27A266a`；iOS SDK 27.0 |
| Flutter / Dart | 3.47.3 / 3.13.3，使用项目固定 SDK |
| 依赖管理 | CocoaPods 1.16.2，由 `Gemfile.lock` 固定；继续使用 CocoaPods |
| 最低支持版本 | iOS 15.6；Podfile 与 Runner 保持一致 |
| 模拟器 | iPad Pro 11-inch (M5)，arm64；iOS 27.0，build `24A434` |
| 模拟器 UDID | `E3B49F40-CB5C-4CDC-A04D-35E0284103A8` |
| 真机 | ZYZ’s iPad Pro，iPad Pro 11-inch (M4)，`iPad16,3`；iPadOS 27.0，build `24A437` |
| 真机 UDID | `00008132-000278923E99001C`；USB 连接、已解锁 |
| 本地 Bundle ID / Team | `com.fuhua.erosfe.step3` / `A9798656MR`，来自被忽略的 `ios/Flutter/Local.xcconfig` |
| 构建模式 | 两端均为 Debug、arm64；分别使用 `iphonesimulator` 和 `iphoneos` |

现有环境检查脚本输出全部 PASS，见 [完整环境记录](environment.log)。实际产物通过 `lipo -archs` 确认为 arm64，通过 `vtool -show-build` 确认为对应平台、最低系统 15.6 和 SDK 27.0。Dart 的 `Platform.version` 中主机标签不作为区分真机和模拟器的依据。

## ML Kit 方案与版本选择

采用 [google_mlkit_commons 0.12.0 的维护者方案](https://pub.dev/packages/google_mlkit_commons/versions/0.12.0)：每次构建根据目标 SDK 切换 vendored ML Kit arm64 对象的 `LC_BUILD_VERSION.platform`，并移除生成的 xcconfig 中针对模拟器的 arm64 排除。Google 尚未提供这组原生库的正式 arm64 模拟器切片，因此同时验证了实际原生识别结果。

| Dart 插件 | 本次精确版本 | 对应原生依赖 |
| --- | --- | --- |
| `google_mlkit_barcode_scanning` | `0.15.0` | GoogleMLKit 9.0.0 / MLKitBarcodeScanning 8.0.0 |
| `google_mlkit_commons` | `0.12.0`，新增直接依赖 | MLKitVision 10.0.0 / MLKitCommon 14.0.0 / MLImage 1.0.0-beta8 |
| `google_mlkit_language_id` | `0.14.0` | MLKitLanguageID 9.0.0 / MLKitNaturalLanguage 10.0.0 |

评估过最新插件组合，其兼容 helper 与 commons 0.12.0 中的 Ruby、Python 文件内容相同，见 [helper 校验记录](helper-version-evaluation.json)。最终选择上表组合，保留同样的原生库和兼容方案，同时避免最新组合要求的 Flutter 3.44 / Dart 3.12 下限。最终组合要求 Flutter 至少 3.32，兼容当前固定的 3.47.3 和现有 macOS CI 使用的 3.41.7；本次没有运行或修改 CI。

Podfile 在 `flutter_install_all_ios_pods` 之后加载维护者 helper，保证首次安装创建插件 symlink 后才能读取文件。保留原有 post_install 设置，移除其中两处 `EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64`，最后调用 helper。Runner 与第三步使用相同的源码和配置。

## 三轮固定输入验收

验收入口先调用真实的 `lib/main.dart`，确认应用的 `HomePage` 已进入 widget 树，然后通过插件调用原生 ML Kit。完成识别后使用项目现有路由进入真实的 `LayoutSettingPage`（“样式”页面）。识别输入来自本地固定文件和固定文本。

| 检查 | 固定输入 / 期望结果 | 模拟器 1 | iPad | 模拟器 2 |
| --- | --- | --- | --- | --- |
| 核心首页 | `HomePage` 存在 | PASS | PASS | PASS |
| QR 条码 | `EROS-FE-STEP4-ARM64` | PASS | PASS | PASS |
| EAN-13 条码 | `5901234123457` | PASS | PASS | PASS |
| 英文识别 | 固定英文句子 → `en` | PASS | PASS | PASS |
| 日文识别 | 固定日文句子 → `ja` | PASS | PASS | PASS |
| 中文识别 | 固定中文句子 → `zh` | PASS | PASS | PASS |
| 核心设置页面 | `LayoutSettingPage` 存在 | PASS | PASS | PASS |

语言识别阈值为 0.5。输入全文及断言位于 [验收入口](../../tool/ios_mlkit_probe.dart)，条码图片及嵌入的相同图片字节位于 [fixtures](../../tool/fixtures/ios_mlkit_images.dart)。没有使用 mock 或线上识别服务。

| 运行顺序 | Xcode 构建用时 | 文件索引 |
| --- | --- | --- |
| 模拟器 1 | 69.9 秒 | [完整日志](simulator-1.log)、[页面截图](simulator-1.png)、[平台](simulator-1-platform.txt)、[ML Kit 状态](mlkit-simulator-1.json) |
| iPad | 52.9 秒；安装启动 31.8 秒 | [完整日志](device-1.log)、[平台](device-1-platform.txt)、[ML Kit 状态](mlkit-device-1.json) |
| 模拟器 2 | 125.4 秒 | [完整日志](simulator-2.log)、[页面截图](simulator-2.png)、[平台](simulator-2-platform.txt)、[ML Kit 状态](mlkit-simulator-2.json) |

[机器可读结果](acceptance-results.json)保留三轮的系统 build、每项期望值、实际值和通过状态；[关键日志](acceptance.log)保留验收标记。两张最终模拟器截图已检查，均显示真实“样式”页面。Flutter 调试连接已正常 detach。

## 切换没有污染另一端产物的证据

没有在切换之间清理 Pods、重新安装依赖或手动还原二进制。三轮依次在同一份 Pods 上构建。

| 核对项目 | 结果 | 文件索引 |
| --- | --- | --- |
| arm64 平台标记 | 五个 framework 中共 468 个有 `LC_BUILD_VERSION` 的 arm64 对象依次为 7（模拟器）→ 2（真机）→ 7（模拟器） | 三份 `mlkit-*.json` |
| 真机恢复原始二进制 | iPad 构建后的六个 ML Kit framework SHA-256 全部与原始 CocoaPods 缓存相同 | [原始缓存](mlkit-original-cache.json)、[真机状态](mlkit-device-1.json) |
| 模拟器处理可重复 | 最后一轮的六个 framework 校验值及平台计数与第一轮完全一致 | [第一轮](mlkit-simulator-1.json)、[最后一轮](mlkit-simulator-2.json) |
| 真机构建保留模拟器产物 | 第一轮模拟器 App 的 46 个 Mach-O / kernel 文件在真机构建后校验值未变 | [模拟器产物校验值](simulator-1-app-hashes.json) |
| 模拟器构建保留真机产物 | 真机 App 的 46 个 Mach-O / kernel 文件在最后一轮模拟器构建后校验值未变 | [真机产物校验值](device-1-app-hashes.json) |
| 共享依赖缓存 | 最后一轮后原始缓存六个二进制未变，且本地 Pods 文件与缓存文件 inode 不同 | [汇总断言](switch-evidence.json) |
| 锁文件 | 按锁安装及三轮构建后，`pubspec.lock`、`ios/Podfile.lock`、`Gemfile.lock` 均未变化 | [安装前后](lockfile-state.json)、[构建后](switch-evidence.json) |

MLKitBarcodeScanning 的 arm64 archive member 没有 `LC_BUILD_VERSION`；其二进制三轮均保持不变，实际 QR 与 EAN-13 识别均成功。没有把它算入上述 468 个已切换标记的对象。[只读平台检查器](inspect_platforms.py)保留了这一差异。

固定最终版本后执行了 `flutter pub get --enforce-lockfile` 和两次 `bundle exec pod install --deployment`，全部成功。安装记录见 [第一次](pod-install-locked-1.log)、[第二次](pod-install-locked-2.log)和 [Dart 按锁安装](pub-get-locked.log)。

## 更改文件索引

| 文件 | 更改目的 |
| --- | --- |
| [ios/Podfile](../../ios/Podfile) | 加载维护者 helper，按 SDK 切换平台标记，移除模拟器 arm64 排除 |
| [ios/Podfile.lock](../../ios/Podfile.lock) | 固定对应原生 ML Kit 及其依赖版本 |
| [pubspec.yaml](../../pubspec.yaml) | 精确固定三个相互兼容的插件版本 |
| [pubspec.lock](../../pubspec.lock) | 固定 Dart 依赖解析及包校验值 |
| [tool/ios_mlkit_probe.dart](../../tool/ios_mlkit_probe.dart) | 本步骤的 Debug 验收入口，复用真实应用启动和页面路由 |
| [tool/fixtures/ios_mlkit_images.dart](../../tool/fixtures/ios_mlkit_images.dart) | 固定条码图片字节和期望内容 |
| [QR 图片](../../tool/fixtures/ios_mlkit_qr.png)、[EAN-13 图片](../../tool/fixtures/ios_mlkit_ean13.png) | 可人工检查的相同固定输入 |
| 本报告目录 | 结果、平台和校验记录；原始日志保留在本地，沿用仓库的 `*.log` 忽略规则 |

## 重复本步骤的命令

先沿用第二步准备流程，在仓库根目录使用固定 SDK。以下是本次实际使用的运行顺序；每轮看到 `STEP4_SUMMARY` 的 `passed: true` 后按 `d` detach，再执行下一轮。固定输入或页面断言失败会输出 `passed: false` 并抛出异常。

```bash
.fvm/flutter_sdk/bin/flutter run --debug --no-pub \
  -d E3B49F40-CB5C-4CDC-A04D-35E0284103A8 \
  -t tool/ios_mlkit_probe.dart --dart-define=STEP4_RUN=simulator-1

.fvm/flutter_sdk/bin/flutter run --debug --no-pub \
  -d 00008132-000278923E99001C \
  -t tool/ios_mlkit_probe.dart --dart-define=STEP4_RUN=device-1

.fvm/flutter_sdk/bin/flutter run --debug --no-pub \
  -d E3B49F40-CB5C-4CDC-A04D-35E0284103A8 \
  -t tool/ios_mlkit_probe.dart --dart-define=STEP4_RUN=simulator-2
```

换设备时使用 `flutter devices` 中的对应 ID。日常开发仍使用默认 `lib/main.dart` 入口；验收入口只在指定 `-t` 时编入应用。平台检查命令分别为 `python3 artifacts/ios-step4-20260930/inspect_platforms.py <label> 7`（模拟器）或末尾使用 `2`（真机），须在对应构建之后执行。

## 本次结果的范围

通过结论覆盖上述 iOS 27.0 arm64 模拟器、iPadOS 27.0 真机、核心页面及固定条码/语言识别输入，不代表所有 ML Kit 场景或相机实时输入均已验证。维护者 helper 修改同一份 Pods 二进制，本次按顺序构建两端，没有验证共享 Pods 下同时构建不同 SDK。

原始日志仍有既有下载路径权限异常、FileUtils 类重名、插件旧生命周期提示，以及 ML Kit 重复 uploader 提示；这些没有阻止上述验收。第三步记录的 iPad 分享问题未在本步骤处理。没有增加第五步的生命周期回归、集成冒烟套件或第六步的统一开发入口与 CI。其他插件版本的探索记录仅保留在本地 `exploration/`，未用于本报告的通过结论。
