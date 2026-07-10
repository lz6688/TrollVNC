# XXTouch Widget 自启动机制 —— 逆向分析技术报告

> 分析对象：`XXTWidgetExtension.appex`（Swift WidgetKit 扩展）+ `libXXTWidgetHelper.dylib`（ObjC/C++ 辅助库）
> 来源：`app.xxtouch.ios_1.3.8-20260402100402/Payload/XXTExplorer.app/PlugIns/XXTWidgetExtension.appex/`
> 目标：iOS 越狱工具 XXTouch 的"锁屏自启动主 App"机制
> 分析日期：2026-07-08

---

## 0. 一句话结论

XXTouch 利用 iOS WidgetKit **每分钟刷新一次**的特性，把小组件刷新当成"心跳触发器"：每次刷新都调用 `libXXTWidgetHelper.dylib` 里的 `+[XXTWidgetHelper launchXXTExplorerIfNecessary]`，该函数通过 **SpringBoardServices 私有 API `SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions` + `SBSApplicationLaunchOptionUnlockDeviceKey`** 在锁屏状态下**解锁设备并前台拉起越狱主 App**，用 `/tmp` 下的标记文件做去重，并对所有敏感字符串做**编译期 XOR 混淆**以规避静态检测。

---

## 1. 模块结构总览

整个自启动由两个二进制协作完成：

| 二进制 | 语言 | 角色 | 体积 |
|---|---|---|---|
| `XXTWidgetExtension` | Swift | WidgetKit 前端：注册小组件、定义视图、每分钟触发 | ~10KB 代码段, 314 函数 |
| `libXXTWidgetHelper.dylib` | ObjC/C++ | 被前端调用的辅助库：判断状态、写标记、拉起主 App | ~7KB 代码段, 139 函数 |

两者通过 ObjC 运行时 `objc_msgSend(OBJC_CLASS_$_XXTWidgetHelper, "launchXXTExplorerIfNecessary")` 解耦——Widget 扩展本身不含任何越狱/私有 API 调用，所有敏感操作都在 dylib 里，便于单独更新和签名。

---

## 2. Widget 扩展侧（`XXTWidgetExtension`）

### 2.1 入口

```swift
@main
struct XXTWidgetBundle: WidgetBundle {
    var body: some Widget {
        XXTWidget()
    }
}
```

`main` (0x93f4) 只做两件事：取 `XXTWidgetBundle` 的协议见证表 → 调 `WidgetBundle.main()`。标准 WidgetKit 启动样板，无特殊逻辑。

### 2.2 Widget 配置（`XXTWidget.body`，0x5d88）

```swift
struct XXTWidget: Widget {
    let kind: String = "XXTWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) {
            XXTWidgetEntryView()
        }
        .configurationDisplayName("XXTTouch")
        .description("添加到桌面以自动启动 XXTouch")
        .supportedFamilies(supportedFamilies)
    }

    var supportedFamilies: [WidgetFamily] {
        var f = [.systemSmall]
        if #available(iOS 16.0, *) { f.append(.accessoryCircular) }   // __isPlatformVersionAtLeast(2,16,0,0)
        return f
    }
}
```

- 主屏小尺寸 `systemSmall` 始终支持；
- 锁屏圆形 `accessoryCircular` 仅 iOS 16+ 支持（通过 `__isPlatformVersionAtLeast(2,16,0,0)` 运行时判断）。

### 2.3 Timeline Provider —— 触发点（0x84c0 / 0x8354）

`Provider` 实现 `TimelineProvider`，三个方法 `getTimeline` / `getSnapshot` / `placeholder` 共享同一段核心逻辑：

```swift
func getTimeline(in context, completion) {
    let colorCode = XXTWidgetHelper.launchXXTExplorerIfNecessary()   // ← 关键副作用
    let entry = SimpleEntry(
        date: Date(),
        iconColor: Color(
            sRGBRed:   Double((colorCode >> 16) & 0xFF) / 255.0,
            green:     Double((colorCode >>  8) & 0xFF) / 255.0,
            blue:      Double( colorCode        & 0xFF) / 255.0,
            opacity:   1.0
        )
    )
    let next = Date().addingTimeInterval(60)          // ← 60 秒后再刷新
    completion(Timeline(entries: [entry], policy: .after(next)))
}
```

**两个关键点**：

1. **每次刷新都调用** `launchXXTExplorerIfNecessary`，这是整个自启动的触发源。
2. **刷新策略 `TimelineReloadPolicy.after(now + 60s)`**：请求系统 60 秒后再次刷新。iOS WidgetKit 会按此节奏持续调用，形成**每分钟一次的心跳**。
3. helper 的返回值（一个 `uint32`）被按 **B/G/R 字节**拆成 RGB 颜色，作为图标主色——所以 widget 图标颜色实时反映"主 App 是否在跑"。

### 2.4 视图层（`XXTWidgetEntryView.body`，0x5868）

按 `EnvironmentValues.widgetFamily` 分三支：

| Family | 渲染 |
|---|---|
| `systemSmall` | `HomeScreenView`：ZStack{ LinearGradient 背景（忽略安全区） + XXTIcon } |
| `accessoryCircular` | `LockScreenCircularView`：锁屏圆形 |
| 其他 | fallback：白色 `Text` |

### 2.5 `XXTIcon`（0x4648）

纯 SwiftUI 自绘：`Path { ... }` 手绘形状 → `LinearGradient(colors: [主色, .dark()], startPoint: .top, endPoint: .bottom)` 填充 → `.frame(width, height)` 居中。无特殊逻辑。

---

## 3. 辅助库侧（`libXXTWidgetHelper.dylib`）—— 核心机制

### 3.1 字符串混淆原理：`ay::obfuscated_data<N, Key, char>`

这是开源的 [Andrivion/obfuscator](https://github.com/Andrivion/obfuscator) 风格的编译期字符串加密。原理：

**编译期**：模板把字符串字面量的每个字节用 key 做异或，存成静态密文缓冲区。`strings` / 静态扫描看不到明文。

**运行期**：首次访问时通过 `__cxa_guard` 保护一次性解密到原位，解密后明文留在静态缓冲区里供后续使用。

**解密算法**（`ay::cipher<char>`，0x5834）：

```c
void cipher(char *data, size_t n, uint64_t key) {
    for (size_t i = 0; i < n; ++i)
        data[i] ^= (key >> (8 * (i % 8))) & 0xFF;   // 8 字节循环 XOR
}
```

即把 64 位 key 拆成 8 个字节，按 `i % 8` 循环异或到密文上。key 就是模板的第二个非类型参数（如 `4171390554486297459`）。

**对象布局**：`obfuscated_data<N,key>` 对象大小为 `N+1`，前 N 字节是密文，第 N 字节是"已解密标志位"（`decrypt()` 检查 `buf[N] & 1`，解密后清零）。

### 3.2 解密出的全部字符串

通过对 8 个 `sub_XXXX` 初始化函数定位 `__const` 段密文源并用对应 key 解密，得到：

| 调用点 | (N, Key) | 密文源地址 | 解密明文 | 用途 |
|---|---|---|---|---|
| `sub_43F8` | (14, 4171390554486297459) | 0x5F6F | `XXT_BUNDLE_ID` | Info.plist 自定义键名 |
| `sub_4528` | (24, 14375339529603991449) | 0x5F7D | `com.xxtouch.XXTExplorer` | 默认 bundle id 兜底 |
| `sub_4654` | (30, 9007561748555066333) | 0x5F95 | `/tmp/.xxtouch.widget-launched` | "已启动"标记文件前缀 |
| `sub_4784` | (18, 9007561748555066333) | 0x5FB3 | `/tmp/.1ferver.pid` | 1ferver 守护进程 pid 文件 |
| `sub_48B0` | (3, 9332581757003338579) | 0x5FC5 | `ok` | 写入标记文件的内容 |
| `sub_49AC` | (30, 9332581757003338579) | 0x5FC8 | `/tmp/.xxtouch.widget-launched` | 同上（不同 key 实例） |
| `sub_4ADC` | (3, 1823317716879916447) | 0x5FE6 | `ok` | 同上 |
| `sub_4BD8` | (39, 1823317716879916447) | 0x5FE9 | `/tmp/.xxtouch.widget-startup-need-lock` | "需要锁屏启动"标记文件前缀 |

### 3.3 `launchXXTExplorerIfNecessary` 完整还原（0x4000）

```objc
+ (uint32_t)launchXXTExplorerIfNecessary {
    NSBundle *bundle = [NSBundle mainBundle];

    // ① 取主 App 的 bundle id：优先 Info.plist 的 XXT_BUNDLE_ID，兜底硬编码默认值
    NSString *appId = [bundle objectForInfoDictionaryKey:@"XXT_BUNDLE_ID"];
    if (!appId) appId = @"com.xxtouch.XXTExplorer";

    NSFileManager *fm = [NSFileManager defaultManager];

    // ② 判断"是否已在运行"：先看 widget 拉起标记，再看 1ferver 守护进程 pid
    BOOL running = [fm fileExistsAtPath:
                       [NSString stringWithFormat:@"%@.%@", @"/tmp/.xxtouch.widget-launched", appId]];
    if (!running) {
        running = [fm fileExistsAtPath:@"/tmp/.1ferver.pid"];
    }

    if (running) {
        return 3502775;        // 0x003566E7 → 已运行状态色
    }

    // ③ 未运行：写两个标记文件
    [@"ok" writeToFile:[NSString stringWithFormat:@"%@.%@", @"/tmp/.xxtouch.widget-launched", appId]
            atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"ok" writeToFile:[NSString stringWithFormat:@"%@.%@", @"/tmp/.xxtouch.widget-startup-need-lock", appId]
            atomically:YES encoding:NSUTF8StringEncoding error:nil];

    // ④ 用 SpringBoardServices 私有 API 拉起主 App，并要求解锁设备
    NSDictionary *opts = @{SBSApplicationLaunchOptionUnlockDeviceKey: @YES};
    BOOL ok = SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions(
                  appId, nil, nil, opts, nil);

    return ok ? 7632505 : 3502775;   // 0x00746E69 : 0x003566E7
}
```

### 3.4 返回值的"颜色编码"含义

返回的 `uint32` 被 Widget 侧按 B/G/R 拆成 RGB：

| 返回值 | 十六进制 | R | G | B | 含义 | 视觉 |
|---|---|---|---|---|---|---|
| `3502775` | `0x003566E7` | 0xE7 | 0x66 | 0x35 | 已运行 / 拉起失败 | 蓝绿色 |
| `7632505` | `0x00746E69` | 0x69 | 0x6E | 0x74 | 刚成功拉起 | 灰紫色 |

即**图标颜色 = 主 App 运行状态指示灯**。

---

## 4. 关键实现方法与原理

### 4.1 自启动触发原理：滥用 WidgetKit 刷新节奏

iOS WidgetKit 的 `TimelineProvider.getTimeline` 通过返回的 `TimelineReloadPolicy` 请求下次刷新时间。本例用 `.after(now + 60s)`，系统会持续每分钟调用一次 `getTimeline`。

**为什么这是可靠的触发源**：
- Widget 扩展由 `extension` 进程承载，即使主 App 被系统杀掉，扩展仍会被系统按节奏唤起；
- 扩展进程有独立的生命周期，不受主 App 进程状态影响；
- 60 秒粒度足够及时（设备重启后最多 1 分钟内自启），又不至于触发系统限流。

**对比其他自启手法**：越狱工具传统用 `LaunchDaemons`（plist 放 `/Library/LaunchDaemons`）做开机自启，但那种方式**无法在用户锁屏时解锁并前台拉起 UI App**——只能拉后台守护进程。本机制补足了"把 UI 主 App 拉到前台"这一环。

### 4.2 解锁并前台拉起原理：SpringBoardServices 私有 API

```c
SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions(
    NSString *bundleIdentifier,
    NSURL *url,
    NSDictionary *options,        // {SBSApplicationLaunchOptionUnlockDeviceKey: @YES}
    ...
);
```

- `SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions` 属于 **`SpringBoardServices.framework`**（私有框架，位于 `/System/Library/PrivateFrameworks/`）。
- `SBSApplicationLaunchOptionUnlockDeviceKey` 是其 launch option 键，值为 `YES` 时**SpringBoard 会先解锁设备（如果锁屏）再把目标 App 拉到前台**。
- 这条 API 需要 `com.apple.springboard.launchapplications` 等私有权限，正常沙盒 App 无法调用——XXTouch 作为越狱工具具备完整 entitlements，故可用。

**效果**：用户锁屏 → Widget 在后台刷新 → 调用此 API → 设备被解锁 + XXTExplorer 主 App 被拉到前台。即**"锁屏一键自启"**。

### 4.3 状态去重原理：`/tmp` 标记文件

用三个文件做轻量状态机：

```
/tmp/.xxtouch.widget-launched.<id>      ← "已被 widget 拉起过" 标记
/tmp/.xxtouch.widget-startup-need-lock.<id>  ← "需要锁屏启动" 标记（给主 App/1ferver 侧消费）
/tmp/.1ferver.pid                      ← 1ferver 守护进程的 pid 文件
```

判断逻辑：

```
running = exists(.widget-launched.<id>)  OR  exists(.1ferver.pid)
```

- 优先看 `.widget-launched.<id>`：widget 自己上次写的标记，避免重复调私有 API。
- 再看 `.1ferver.pid`：1ferver 是 XXTouch 的常驻守护进程，其 pid 文件存在说明越狱环境已就绪。
- 两个都不存在才执行拉起，并先写标记再拉起（防止拉起失败导致无限重试）。

**为什么放 `/tmp`**：`/tmp` 在重启后会被清空，正好实现"重启后重新自启"的语义；且越狱环境下 `/tmp` 全局可读写，跨进程可见。

### 4.4 反静态检测原理：编译期字符串混淆

所有敏感路径（`/tmp/.xxtouch.*`、bundle id、私有 API 调用周边字符串）都通过 `ay::obfuscated_data<N,Key,char>` 在编译期异或加密，运行时首次访问才解密。

**对抗的检测手段**：
- `strings` 命令 / 二进制扫描器：看不到明文路径，无法通过文件名特征识别。
- 静态分析自动化规则（如 App Store 扫描、MDM 合规检查）：无法匹配 `/tmp/.xxtouch` 等可疑路径。
- 简单的 `grep` 式 IOC：失效。

**局限**：
- 解密后明文仍在内存静态区，运行时内存 dump 可见；
- key 是模板参数，硬编码在符号名里（如 `obfuscated_data<14, 4171390554486297459>`），逆向后一眼可读——这是**混淆（obfuscation）而非加密**，目的是抬高静态扫描门槛，不是对抗人工逆向。

### 4.5 解耦设计原理：Widget + Helper dylib 分离

- Widget 扩展（Swift）只做 UI + 触发，**不含任何私有 API 调用**，可以通过更宽松的签名/审核。
- 所有敏感操作集中在 `libXXTWidgetHelper.dylib`，可以单独替换/更新而无需重新构建 Widget 扩展。
- 通过 ObjC 运行时 `objc_msgSend` 弱耦合，Widget 扩展甚至不需要链接 dylib 的符号（只靠 `OBJC_CLASS_$_XXTWidgetHelper` 类引用）。

---

## 5. 完整运行时序

```
┌─────────────────────────────────────────────────────────────────┐
│  系统按 WidgetKit 节奏（每 60s）唤起 XXTWidgetExtension 进程    │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
        Provider.getTimeline(in:, completion:)
                            │
                            ▼
        XXTWidgetHelper.launchXXTExplorerIfNecessary   (跨 dylib 调用)
                            │
            ┌───────────────┴───────────────┐
            ▼                               ▼
   exists(/tmp/.xxtouch.widget-        exists(/tmp/.1ferver.pid)
          launched.<id>)?              ?
            │                               │
            └───────────────┬───────────────┘
                            ▼
                   任一为真 → 返回 0x003566E7（已运行色）
                            │
                   两者皆无 ↓
                            │
        write /tmp/.xxtouch.widget-launched.<id>        = "ok"
        write /tmp/.xxtouch.widget-startup-need-lock.<id> = "ok"
                            │
                            ▼
        SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions(
            "com.xxtouch.XXTExplorer",
            options = {UnlockDevice: YES})
                            │
                    ┌───────┴───────┐
                    ▼               ▼
              成功 → 0x00746E69   失败 → 0x003566E7
                            │
                            ▼
        SpringBoard 解锁设备 + 前台拉起 XXTExplorer
                            │
                            ▼
        Widget 用返回值着色 XXTIcon，completion(Timeline)
                            │
                            ▼
        系统在 now+60s 后再次唤起 → 回到顶部
```

---

## 6. 安全/对抗视角小结

| 维度 | 手法 | 目的 |
|---|---|---|
| 触发 | 滥用 WidgetKit 60s 刷新节奏 | 即使主 App 被杀也能持续自启 |
| 拉起 | SpringBoardServices 私有 API + UnlockDevice | 锁屏状态下解锁并前台拉起 UI App |
| 去重 | `/tmp` 标记文件状态机 | 避免重复拉起、重启后重新自启 |
| 隐蔽 | `ay::obfuscated_data` 编译期 XOR 混淆 | 抬高静态扫描门槛，规避 strings/IOC 检测 |
| 解耦 | Widget 扩展 + Helper dylib 分离 | 敏感操作集中、可单独更新、降低审核风险 |
| 反馈 | 返回值编码成图标 RGB 颜色 | 用户通过 widget 颜色感知运行状态 |

**整体定性**：这是一套设计完整、工程化程度高的越狱工具**锁屏自启动机制**。它不是漏洞利用，而是对 iOS 既有能力（WidgetKit + 私有 API + 越狱权限）的组合运用。核心创新点在于**把 Widget 刷新当成可靠的心跳源**，补足了传统 `LaunchDaemons` 无法"解锁并前台拉起 UI App"的缺口。

---

## 附录 A：关键地址速查

### Widget 扩展（imagebase 0x100000000）
| 地址 | 符号 | 作用 |
|---|---|---|
| 0x1000093f4 | `main` | 入口，调 WidgetBundle.main() |
| 0x100005d88 | `XXTWidget.body.getter` | Widget 配置（kind/displayName/supportedFamilies） |
| 0x1000084c0 | `Provider.getTimeline` (specialized) | 每分钟触发 + 调 helper |
| 0x100008354 | `Provider.getSnapshot` (specialized) | 同上 |
| 0x100005868 | `XXTWidgetEntryView.body.getter` | 按 family 分支渲染 |
| 0x100004648 | `XXTIcon.body.getter` | 自绘渐变图标 |

### Helper dylib（imagebase 0x0）
| 地址 | 符号 | 作用 |
|---|---|---|
| 0x4000 | `+[XXTWidgetHelper launchXXTExplorerIfNecessary]` | 核心逻辑 |
| 0x5834 | `ay::cipher<char>` | 8 字节循环 XOR 解密 |
| 0x57dc 等 | `ay::obfuscated_data::decrypt` | 各实例的解密入口 |
| 0x5F6F–0x6010 | `__const` | 8 段密文缓冲区 |
| 0xC290 | (import) | `SBSLaunchApplicationWithIdentifierAndURLAndLaunchOptions` |
| 0xC288 | (import) | `SBSApplicationLaunchOptionUnlockDeviceKey` |

## 附录 B：解密脚本（IDA Python）

```python
import idaapi, idautils, idc, ida_funcs, ida_bytes, ida_name

def decrypt(buf, n, key):
    out = bytearray(buf[:n])
    for i in range(n):
        out[i] ^= (key >> (8 * (i % 8))) & 0xFF
    return bytes(out)

subs = {
    0x43F8: (14, 4171390554486297459),
    0x4528: (24, 14375339529603991449),
    0x4654: (30, 9007561748555066333),
    0x4784: (18, 9007561748555066333),
    0x48B0: (3,  9332581757003338579),
    0x49AC: (30, 9332581757003338579),
    0x4ADC: (3,  1823317716879916447),
    0x4BD8: (39, 1823317716879916447),
}

def find_adrl_target(ea):
    f = ida_funcs.get_func(ea); end = f.end_ea; cur = ea
    while cur < end:
        if idc.print_insn_mnem(cur) in ("ADRL", "ADRP"):
            tgt = idc.get_operand_value(cur, 1)
            if 0x5e00 <= tgt <= 0x6010:
                return tgt
        cur = idc.next_head(cur, end)
    return None

for sub, (n, key) in subs.items():
    tgt = find_adrl_target(sub)
    raw = ida_bytes.get_bytes(tgt, n + 1)
    print(f"sub_{sub:X} -> {decrypt(raw, n, key)!r}")
```
