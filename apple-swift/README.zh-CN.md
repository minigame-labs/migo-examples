> English: [README.md](README.md)

# iOS 与 macOS —— Swift，`MigoGameView`

一个 iOS App 和一个 macOS App，通过 Apple SDK 的产品接口运行
[`../games/demo`](../games/)：安装游戏包，再把它加载进 `MigoGameView`。
两个 App 共用做这件事的代码（[`Shared/ExampleGame.swift`](Shared/ExampleGame.swift)），
区别只在承载视图的窗口。

## 运行

```bash
bash run.sh macos
bash run.sh ios-simulator
```

脚本会把 Apple SDK 解析到 `sdk/`，用 `xcodebuild` 构建，然后运行游戏：macOS 上开一个窗口，
iOS 上跑在 iPhone 模拟器里。传一个秒数则运行这么久后退出，退出码表示游戏是否就绪并拿到了帧：

```bash
bash run.sh macos 10
```

也可以先解析一次 SDK，再用 Xcode 打开 `MigoExample.xcodeproj`：

```bash
bash ../scripts/resolve-migo-artifact.sh apple-sdk sdk
open MigoExample.xcodeproj
```

要在 iPhone 真机上运行，选中 `MigoExample-iOS` target，在 *Signing & Capabilities* 里设置你的 Team。

## 环境要求

- Xcode 16 或更高
- iOS 15.2 或更高；macOS 11 或更高的 Mac

## 工程里演示了什么

| 步骤 | 位置 |
|---|---|
| 每个平台链接一个产品 | 本地包 `Migo`（`sdk/`）：iOS 用 `MigoApplePerformancePlus`，macOS 用 `MigoMacV8` |
| 安装 App 自带的游戏，每个构建版本只装一次 | `ExampleGame.makeView` 里的 `MigoGameInstaller.install` |
| 运行游戏并跟踪它的状态 | `ExampleGame.run` 里的 `MigoGameView.loadGame` 与 `onEvent` |
| 把 iOS App 锁定在游戏的方向 | `GameViewController.supportedInterfaceOrientations` 与 target 的方向设置 |
| 在 macOS 上允许 V8 的 JIT | `macOS/MigoExample.entitlements`（`com.apple.security.cs.allow-jit`）配合 hardened runtime |
| 在 macOS App 签名前嵌入 ANGLE | macOS target 的 *Embed ANGLE* 构建阶段 |

iOS 不需要手动嵌入任何东西：SDK 把 ANGLE 声明为 framework 依赖，由 Xcode 嵌入。
macOS 上 ANGLE 是一对 dylib，由构建阶段复制到 `Contents/Frameworks` 并用 App 的身份签名；
target 的 runpath 包含 `@executable_path/../Frameworks`。

游戏以 `.unsigned` 安装，因为它就在这个已签名的 App 里。App 下载的游戏应当签名，
并用 `.verified(publicKey:)` 安装；包格式见 SDK 的 README。

[`wx-adapter-demo`](../games/wx-adapter-demo/) 在这里跑不了：它是基于 `wx.*` 写的，
而 `MigoGameView` 不安装 `wx.*`。
