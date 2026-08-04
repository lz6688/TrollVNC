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
3. `TrollVNCAutostartProvider` 仅在 `getTimeline` 中调用 `TrollVNCWidgetHelper.launchTrollVNCIfNecessary()`；`placeholder` 和 `getSnapshot` 只生成静态预览，避免在小组件图库中启动 TrollVNC。
4. helper 从 Widget 的 `Info.plist` 读取 `XXT_BUNDLE_ID`，目标为 `com.82flex.TrollVNCApp`。
5. helper 使用只读的现代越狱信号判断当前环境：已注册的越狱 Mach service、已加载的注入 dylib、有效的 `/var/jb` bootstrap、异常 bind mount，以及“非快照根文件系统 + 多个 rootful 文件”的组合。检测不执行越狱二进制，也不写系统目录。
6. 从越狱安装路径启动的 manager/server 会向 App Group `group.com.82flex.TrollVNCApp` 写入当前 `KERN_BOOTTIME` 和 PID；该状态只用于验证 TrollVNC 越狱服务是否存活，不参与越狱环境判定。helper 还会用 manager 已有的 `127.0.0.1:46751` alive 端口识别 TrollStore 服务。
7. 如果确认当前是活跃越狱环境且 TrollVNC 服务已经存活，helper 只检查/写入 App Group 中的 `.trollvnc.widget-launched.<bundle id>` 标记并调用 `SBSLockDevice()` 拉起锁屏，不启动 `com.82flex.TrollVNCApp`。
8. 如果确认当前是活跃越狱环境但 TrollVNC 服务没有存活，helper 清理本次自启标记并直接返回，不启动 `com.82flex.TrollVNCApp`，避免越狱后仍由 TrollStore Widget 拉起服务。
9. 只有在未越狱环境且服务未运行时，helper 才向 App Group 写入 `.trollvnc.widget-startup-need-lock.<bundle id>`。
10. helper 调用 `SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions`，并把 unlock options 同时传入 `appOptions` 和 `launchOptions`；若失败，再 fallback 到 `SBSLaunchApplicationWithIdentifierAndLaunchOptions`，最多重试 3 次。
11. 只有 SpringBoardServices 返回成功后，helper 才向 App Group 写入 `.trollvnc.widget-launched.<bundle id>`；失败会清理标记，等待下次 Widget 心跳继续重试。
12. Widget 返回的颜色值用于显示当前状态，并请求 15 秒后刷新。

## 关键实现点

- `TrollVNCAutostartWidget.swift` 使用 `.after(Date().addingTimeInterval(15))` 形成更积极的刷新请求；系统仍可能按 WidgetKit 策略延后调度。
- Widget 支持 `.systemSmall`，iOS 16+ 额外支持 `.accessoryCircular`。
- helper 使用 ObjC++ 实现，链接项目已有的 `SpringBoardServices.tbd`。
- helper 中 bundle id、标记文件名等启动相关字符串使用编译期 XOR 模板混淆；App Group ID 必须出现在 entitlement 中，因此不做字符串隐藏。
- 越狱判断参考现代检测项目的信号分类独立实现，没有复制第三方源码。强信号包括 Mach service、进程内注入 dylib、验证后的 rootless bootstrap 和异常 bind mount；rootful 文件只有和非快照根文件系统同时出现时才生效，避免单个残留文件直接触发。
- `widget-launched` 和 `startup-need-lock` 标记内容也是当前开机标识；App Group 文件可以跨重启保留，但旧内容不会在新开机周期生效。
- 主 App target 依赖并嵌入 Widget 扩展；Widget target 依赖并嵌入 helper dylib。
- 主 App、Widget、helper、manager/server 共用 `TrollVNC/TrollVNC.entitlements`，其中声明 App Group，并继续通过 ldid pseudo-sign 满足 TrollStore 场景下的私有 API 权限需求。

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

如需重复测试，可以重启设备；App Group 中旧标记虽然仍存在，但因为开机标识变化而自动失效。若要在同一次开机周期内重复测试，需要清理 App Group 中的 `.trollvnc.widget-launched.*` 和 `.trollvnc.widget-startup-need-lock.*`。

## 已知说明

直接运行完整 `xcodebuild -scheme TrollVNC` 可能会被主 App 既有的 `PACKAGE_VERSION` 宏转义问题卡住；这不是 Widget/helper 改动引入的问题。TrollStore 包验证建议使用现有 Theos bootstrap 打包流程。
