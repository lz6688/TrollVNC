# TrollVNC Widget 自启动实现说明

## 背景

重启后设备处于非越狱状态，不能依赖 LaunchDaemon 或越狱态 manager 先行启动。当前实现参考 `XXTWidget自启动机制_技术分析.md` 的机制，使用 WidgetKit 的定时刷新作为心跳触发源，在 Widget 扩展进程内通过 helper dylib 调用 SpringBoardServices 私有 API 拉起 TrollVNC 主 App。

目标包型为 TrollStore/tipa。主 App 嵌入 Widget 扩展，Widget 扩展再嵌入 helper dylib，打包到 `Payload/TrollVNC.app` 后由 TrollStore 安装。

## 新增模块

| 模块 | 路径 | 作用 |
|---|---|---|
| Widget 扩展 | `app/TrollVNC/TrollVNCAutostartWidget/` | WidgetKit 入口、视图、TimelineProvider 心跳 |
| Helper dylib | `app/TrollVNC/TrollVNCWidgetHelper/` | 状态判断、标记文件写入、SpringBoardServices 拉起 |
| Xcode target | `TrollVNCAutostartWidget` | 生成 `TrollVNCAutostartWidget.appex` |
| Xcode target | `TrollVNCWidgetHelper` | 生成 `libTrollVNCWidgetHelper.dylib` |

## 运行流程

1. 用户安装 TrollStore 版 TrollVNC，并把 TrollVNC 小组件添加到桌面或锁屏。
2. iOS 按 WidgetKit timeline 策略唤醒 `TrollVNCAutostartWidget.appex`。
3. `TrollVNCAutostartProvider` 在 `placeholder`、`getSnapshot`、`getTimeline` 中调用 `TrollVNCWidgetHelper.launchTrollVNCIfNecessary()`。
4. helper 从 Widget 的 `Info.plist` 读取 `XXT_BUNDLE_ID`，目标为 `com.82flex.TrollVNCApp`。
5. helper 先检查 `/tmp/.trollvnc.widget-launched.<bundle id>`，避免重复拉起。
6. 如果没有 widget 标记，再检查 TrollVNC 现有 manager/server pid 锁文件，并用 `kill(pid, 0)` 验证进程是否仍存活。
7. 若未运行，helper 写入：
   - `/tmp/.trollvnc.widget-launched.<bundle id>`
   - `/tmp/.trollvnc.widget-startup-need-lock.<bundle id>`
8. helper 调用 `SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions`，并传入 `SBSApplicationLaunchOptionUnlockDeviceKey: YES` 拉起主 App。
9. Widget 返回的颜色值用于显示当前状态，并请求 60 秒后刷新。

## 关键实现点

- `TrollVNCAutostartWidget.swift` 使用 `.after(Date().addingTimeInterval(60))` 形成每分钟一次的刷新请求。
- Widget 支持 `.systemSmall`，iOS 16+ 额外支持 `.accessoryCircular`。
- helper 使用 ObjC++ 实现，链接项目已有的 `SpringBoardServices.tbd`。
- helper 中 bundle id、标记路径、pid 路径等敏感字符串使用编译期 XOR 模板混淆，避免直接出现在 `strings` 结果中。
- 主 App target 依赖并嵌入 Widget 扩展；Widget target 依赖并嵌入 helper dylib。
- Widget 和 helper 都使用 `TrollVNC/TrollVNC.entitlements` 做 ldid pseudo-sign，满足 TrollStore 场景下私有 API 权限需求。

## 构建验证

只验证新增 Widget/helper target：

```sh
xcodebuild -project app/TrollVNC/TrollVNC.xcodeproj \
  -target TrollVNCAutostartWidget \
  -configuration Release \
  -sdk iphoneos \
  -destination generic/platform=iOS \
  SYMROOT=/tmp/TrollVNCWidgetOnlyBuild/Build \
  OBJROOT=/tmp/TrollVNCWidgetOnlyBuild/Intermediates \
  CODE_SIGNING_ALLOWED=NO
```

检查产物：

```sh
find /tmp/TrollVNCWidgetOnlyBuild/Build/Release-iphoneos/TrollVNCAutostartWidget.appex -maxdepth 3 -type f
```

期望包含：

```text
TrollVNCAutostartWidget.appex/TrollVNCAutostartWidget
TrollVNCAutostartWidget.appex/Frameworks/libTrollVNCWidgetHelper.dylib
TrollVNCAutostartWidget.appex/Info.plist
```

检查 helper 链接：

```sh
otool -L /tmp/TrollVNCWidgetOnlyBuild/Build/Release-iphoneos/TrollVNCAutostartWidget.appex/Frameworks/libTrollVNCWidgetHelper.dylib
```

期望包含：

```text
/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices
```

检查敏感字符串是否没有明文落入 helper：

```sh
rg -a -n "/tmp/\\.trollvnc|/var/mobile/Library/Caches/com\\.82flex\\.trollvnc|XXT_BUNDLE_ID|widget-launched|startup-need-lock" \
  /tmp/TrollVNCWidgetOnlyBuild/Build/Release-iphoneos/TrollVNCAutostartWidget.appex/Frameworks/libTrollVNCWidgetHelper.dylib
```

期望没有输出。

## TrollStore 包验证

用现有 bootstrap/tipa 流程打包：

```sh
source devkit/bootstrap.sh
FINALPACKAGE=1 gmake clean package
```

检查 tipa 内是否带上 Widget 和 helper：

```sh
zipinfo -1 packages/TrollVNC_*.tipa | rg 'PlugIns/TrollVNCAutostartWidget.appex|libTrollVNCWidgetHelper.dylib'
```

期望包含：

```text
Payload/TrollVNC.app/PlugIns/TrollVNCAutostartWidget.appex/
Payload/TrollVNC.app/PlugIns/TrollVNCAutostartWidget.appex/Frameworks/libTrollVNCWidgetHelper.dylib
```

## 真机验证

1. 用 TrollStore 安装新的 `.tipa`。
2. 打开一次 TrollVNC，确认主 App 可正常启动。
3. 添加 TrollVNC 桌面小组件或锁屏圆形小组件。
4. 重启设备。
5. 重启后不要手动打开 TrollVNC，等待 1 到 2 分钟。
6. 预期 TrollVNC 被 Widget 心跳自动拉起到前台。

如需重复测试，推荐重启设备，因为 `/tmp/.trollvnc.widget-launched.*` 会随重启清空。若不重启，helper 会按去重逻辑避免重复拉起。

## 已知说明

直接运行完整 `xcodebuild -scheme TrollVNC` 可能会被主 App 既有的 `PACKAGE_VERSION` 宏转义问题卡住；这不是 Widget/helper 改动引入的问题。TrollStore 包验证建议使用现有 Theos bootstrap 打包流程。
