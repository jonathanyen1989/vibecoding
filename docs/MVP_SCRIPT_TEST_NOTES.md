# FocusLens macOS MVP 脚本测试记录

日期：2026-07-07

## 当前结论

最小 MVP 阶段先使用脚本方式运行：

```bash
cd "/Users/xuanmu/Desktop/Mywork/all kind of test/FocusLensMacMVP"
swift run FocusLensMacMVP
```

测试成功的行为：

- `Control + W` 可以触发 FocusLens。
- 主屏可以截到真实窗口内容，不是桌面壁纸。
- 副屏可以截到真实窗口内容，包括微信窗口，不是桌面壁纸。
- `Esc` 退出当前聚焦状态。
- 连续按第二次 `Control + W` 不应退出或重新截图；只有退出后才能重新触发。

## 当前可用实现方式

### 1. MVP 先不使用 `.app` 包测试

脚本阶段不要优先打包成 `dist/FocusLens.app` 测试。原因是 macOS 的屏幕录制权限绑定到当前可执行体和签名身份。

在没有稳定开发者证书时，打包脚本使用 ad-hoc 签名：

```bash
codesign --force --deep --sign -
```

每次重新构建后 `CDHash` 可能变化，macOS 会把它当成新的程序，导致之前授予的屏幕录制权限失效。

因此当前开发阶段先使用：

```bash
swift run FocusLensMacMVP
```

等 MVP 行为稳定后，再处理稳定签名、权限、打包和公证。

### 2. 脚本阶段优先使用 `CGWindowListCreateImage`

当前脚本测试阶段优先使用：

```swift
CGWindowListCreateImage(
    displayBounds,
    .optionOnScreenOnly,
    kCGNullWindowID,
    [.bestResolution]
)
```

它在当前测试环境里可以截到真实窗口内容，包括主屏和副屏。

`ScreenCaptureKit` 仍然保留为 fallback，但在 app 包权限不稳定时，容易出现只截到桌面背景的问题。MVP 阶段先不把它作为主路径。

### 3. `.app` 包权限检查只在 app bundle 运行时启用

脚本运行时不要用 `.app` 的权限检查挡住截图：

```swift
let isRunningAsAppBundle = Bundle.main.bundlePath.hasSuffix(".app")
guard !isRunningAsAppBundle || ScreenRecordingPermission.isGranted else {
    ...
    return
}
```

这样脚本测试不会被 app 包的 TCC 权限身份干扰。

### 4. 副屏窗口坐标要区分全局坐标和 screen-local 坐标

副屏窗口只显示顶部一条的根因是：把全局屏幕坐标传给了 `NSWindow(..., screen:)`。

错误思路：

```swift
super.init(contentRect: overlayFrame, ..., screen: screen)
```

其中 `overlayFrame` 可能是类似：

```text
(-247, 982, 1920, 1080)
```

对 `screen:` 初始化器来说，应使用目标屏幕内的局部坐标：

```swift
let overlayFrame = screen.focusLensOverlayFrame
let screenLocalFrame = NSRect(origin: .zero, size: overlayFrame.size)

super.init(
    contentRect: screenLocalFrame,
    styleMask: [.borderless],
    backing: .buffered,
    defer: false,
    screen: screen
)
```

否则窗口会被放到副屏可见区域之外，只露出顶部一条。

### 5. 选屏逻辑使用 CoreGraphics 命中鼠标所在 display

不要只依赖 `NSScreen.frame.contains(mouse)`，多屏上下排列时容易混淆 AppKit 坐标和 CoreGraphics 坐标。

当前更可靠的方式是：

```swift
let point = CGEvent(source: nil)?.location
CGGetDisplaysWithPoint(point, 1, &matchingDisplay, &displayCount)
```

然后用 `displayID` 找到对应的 `NSScreen`。

## 遇到的主要难点

### 难点 1：看起来像副屏错位，其实有两类问题

这次出现过两种不同问题：

1. 覆盖窗口只显示在副屏顶部一条。
2. 覆盖窗口显示完整，但底图是桌面壁纸，不是真实窗口内容。

第一类是窗口坐标问题；第二类是截图权限或截图 API 路径问题。两者现象相似，但根因不同。

### 难点 2：`.app` 重签名导致权限反复失效

用户已经多次手动开启屏幕录制权限，但每次重新构建 `.app` 后，ad-hoc 签名导致 macOS 认为这是新的可执行体。

所以继续要求用户反复手动打开权限是错误方向。正确策略是：

1. MVP 阶段先回到 `swift run`。
2. 功能稳定后再解决稳定签名。
3. 发布阶段再处理 Developer ID 签名和 notarization。

### 难点 3：ScreenCaptureKit 可能只返回桌面背景

在当前测试过程中，`ScreenCaptureKit` 路径保存的截图曾只包含桌面背景和菜单栏，没有微信窗口。

判断方法：

```bash
cat /tmp/focuslens-display.log
open /tmp/focuslens-capture-display-2.png
```

如果保存的 PNG 本身就是壁纸，说明问题在截图阶段，不是绘制阶段。

### 难点 4：日志必须区分 selected display 和 captured image

关键诊断日志：

```text
trigger mouse=... selectedDisplay=... screenFrame=... overlayFrame=... displayBounds=...
capture selectedDisplay=... imagePixels=... screenPoints=... scale=...
```

这些日志帮助区分：

- 鼠标是否命中正确显示器。
- 覆盖窗口尺寸是否正确。
- 截图像素是否匹配屏幕倍率。
- 截图文件是否真实包含窗口内容。

## 当前测试命令

启动：

```bash
cd "/Users/xuanmu/Desktop/Mywork/all kind of test/FocusLensMacMVP"
swift run FocusLensMacMVP
```

查看日志：

```bash
cat /tmp/focuslens-display.log
```

查看最近保存的截图：

```bash
open /tmp/focuslens-capture-display-1.png
open /tmp/focuslens-capture-display-2.png
```

停止脚本版：

```bash
pkill -f FocusLensMacMVP
```

## 下一步建议

1. 继续在 `swift run` 模式下验证核心交互：截图、拖拽、放大、退出、再次启动。
2. 确认主屏和副屏都稳定后，再恢复 `.app` 打包。
3. 打包阶段必须使用稳定代码签名身份，否则屏幕录制权限会继续反复失效。
4. 发布阶段再做 Developer ID 签名和 Apple notarization。
