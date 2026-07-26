# Migo Android Demo

[Migo](https://github.com/minigame-labs/migo)(嵌入式 HTML5 / 小游戏的 WebView 替代方案 —— 开源、高性能、跨引擎的原生游戏运行时)的 Android 示例项目。

## 快速开始

### 1. 构建 Migo AAR

当前 Demo 默认依赖本地 `../migo` 仓库产物：

- `../migo/platforms/android/dist/migo-debug.aar`

先在 `migo` 仓库执行：

```bash
cd ../migo
bash scripts/build-aar.sh debug
```

如果你希望改用 release AAR，可先构建：

```bash
cd ../migo
bash scripts/build-aar.sh release
```

然后按需修改 `app/build.gradle.kts` 中的 AAR 路径。

### 2. 准备游戏文件

游戏文件需要放置到设备的应用私有目录，路径格式为：

```
/data/data/com.minigame.androiddemo/files/migo/games/{gameId}/code/
├── game.js          # 游戏入口文件
├── images/          # 图片资源
├── workers/         # Worker 脚本目录（如有）
└── ...              # 其他资源文件
```

其中 `{gameId}` 是游戏的唯一标识符（字母数字、下划线、连字符，1-64字符）。

示例：推送 `demo` 游戏：

```bash
adb push your-game/ /data/data/com.minigame.androiddemo/files/migo/games/demo/code/
```

> 注意：SDK 现在不会自动读取 `game.json`。
> 本 Demo 已在宿主侧实现 `code/game.json` 读取，并在创建 `RuntimeConfig` 时注入
> `workers` / `subPackages` / `deviceOrientation`（映射到 `startupOrientation`）。
> 你也可以手动注入：

```java
RuntimeConfig config = new RuntimeConfig.Builder(context)
    .setWorkersPath("workers")
    .setStartupOrientation("landscape")
    // .addSubPackage("stage1", "subpackages/stage1")
    .build();
```

### 3. 构建运行

使用 Android Studio 打开项目，或通过命令行构建：

```bash
./gradlew assembleDebug
adb install app/build/outputs/apk/debug/app-debug.apk
```

## 两种集成方式

Demo 仅保留两种官方接入方式：

### 方式 1：MigoGameActivity（最简单）

一行代码启动游戏，SDK 内部处理全部生命周期、Surface 管理和触摸事件。

```java
import com.migo.runtime.MigoGameActivity;

// 一行启动
MigoGameActivity.launch(context, "demo", "game.js");

// 或带自定义配置
RuntimeConfig config = new RuntimeConfig.Builder(context)
    .setDebugEnabled(true)
    .build();
MigoGameActivity.launch(context, "demo", "game.js", config);
```

### 方式 2：MigoGameView（嵌入式）

将游戏作为 View 嵌入到任意布局中，适合需要在游戏周围放置原生 UI 元素的场景。

```java
import com.migo.runtime.MigoGameView;

MigoGameView gameView = new MigoGameView(context);

// 配置
RuntimeConfig config = new RuntimeConfig.Builder(context)
    .setDebugEnabled(true)
    .build();
gameView.setConfig(config);

// 设置监听器
gameView.setGameListener(listener);

// 添加到布局
myLayout.addView(gameView);

// 加载游戏
gameView.loadGame("demo", "game.js");

// 在 session 创建回调中注册 handler（startGame 前）
gameView.setSessionCreatedListener(session -> {
    session.setAuthHandler(authHandler);
    session.setGameLogHandler(gameLogHandler);
    session.setSubpackageHandler(subpackageHandler);
});
```

## 监听事件

```java
import com.migo.runtime.callback.GameSessionListener;

session.setListener(new GameSessionListener() {
    @Override
    public void onGameReady() {
        // 游戏加载完成，可以隐藏加载画面
    }

    @Override
    public void onGameExit(int exitCode) {
        // 游戏退出，exitCode == 0 表示正常退出
    }

    @Override
    public void onError(MigoException exception) {
        int code = exception.getErrorCode();
        String msg = exception.getMessage();
        boolean recoverable = exception.isRecoverable();
        // recoverable=true: session can continue
        // recoverable=false: session must be restarted
    }
});
```

## 宿主 Handler（最新 API）

`GameSession` 当前支持以下宿主回调：

- `setAuthHandler(AuthHandler)`：处理 `wx.login` / `wx.checkSession` / `wx.getUserInfo` / `wx.getPhoneNumber`
- `setGameLogHandler(GameLogHandler)`：接收小游戏上报日志（JSON）
- `setSubpackageHandler(SubpackageHandler)`：处理 `loadSubpackage` / `preDownloadSubpackage`

Demo 中的对应 sample 实现：

- `app/src/main/java/com/minigame/androiddemo/auth/ProxyAuthHandler.java`
- `app/src/main/java/com/minigame/androiddemo/DemoGameLogHandler.java`
- `app/src/main/java/com/minigame/androiddemo/DemoSubpackageHandler.java`

### Auth Relay 快速实施

Relay 客户端入口：

- `app/src/main/java/com/minigame/androiddemo/auth/ProxyAuthHandler.java`

请求协议：

- Endpoint: `POST {relayBaseUrl}/auth/request`
- Body: `{"action":"login|checkSession|getUserInfo|getPhoneNumber","params":{...},"gameId":"..."}`

返回协议：

- 成功：`login/getPhoneNumber` 返回 `{"code":"..."}`，`checkSession` 返回 `{}`，`getUserInfo` 返回 `{"userInfo":...}`
- 失败：`{"error":"reason","errno":123}`（`errno` 可选）

Demo 接入点：

- `DebugMigoGameActivity` 在 `onSessionCreated(...)` 注册 `ProxyAuthHandler`
- `EmbeddedGameActivity` 在 `setSessionCreatedListener(...)` 注册 `ProxyAuthHandler`

URL 配置：

- 模拟器：`http://10.0.2.2:9527`
- 真机：`http://<你的电脑局域网IP>:9527`

排查建议：

- 看 `ProxyAuthHandler` 和 Activity 日志是否收到回调
- 确认 relay 收到 `/auth/request`
- 确认 `gameId` 路由与桌面侧代理实例一致

## 新增 API

### 会话状态监听

```java
session.setOnStateChangeListener((session, oldState, newState) -> {
    Log.d("Game", "State: " + oldState + " -> " + newState);
});

// 查询当前状态
SessionState state = session.getState(); // CREATED, RUNNING, PAUSED, DESTROYED
```

### 性能监控

```java
PerformanceSnapshot perf = session.getPerformanceSnapshot();
if (perf != null) {
    Log.d("Perf", "FPS=" + perf.fps + " frameTime=" + perf.frameTimeMs + "ms");
}
```

### Host ↔ JS 通信

```java
// Java → JS：执行 JavaScript 代码
session.evaluateJavaScript("console.log('hello from host')");

// JS → Java：接收游戏消息
session.setMessageHandler((type, payload) -> {
    Log.d("Game", "Message: type=" + type + " payload=" + payload);
});
```

### 启动失败处理

继承 `MigoGameActivity` 并重写 `onLaunchFailed`：

```java
@Override
protected void onLaunchFailed(int errorCode, String message) {
    Toast.makeText(this, "启动失败: " + message, Toast.LENGTH_LONG).show();
    super.onLaunchFailed(errorCode, message); // 默认调用 finish()
}
```

### 错误诊断

```java
MigoRuntime runtime = MigoRuntime.getInstance();
if (!runtime.isNativeLoaded()) {
    Throwable error = runtime.getNativeLoadError();
    Log.e("Init", "Native load failed", error);
}
```

## 项目结构

```
app/
└── src/main/
    ├── java/.../
    │   ├── MainActivity.java           # Demo 选择器
    │   ├── EmbeddedGameActivity.java   # 方式 2: MigoGameView 嵌入
    │   ├── DebugMigoGameActivity.java  # 方式 1: MigoGameActivity 调试封装
    │   ├── GameConfigLoader.java       # 读取并解析 code/game.json
    │   ├── RuntimeConfigCompat.java    # game.json 字段注入 RuntimeConfig
    │   ├── DemoGameLogHandler.java     # GameLogHandler sample
    │   ├── DemoSubpackageHandler.java  # SubpackageHandler sample
    │   ├── auth/
    │   │   └── ProxyAuthHandler.java   # AuthHandler sample
    └── AndroidManifest.xml
```

## 游戏目录结构

```
/data/data/{packageName}/files/migo/games/{gameId}/
├── code/           # 游戏代码目录 (只读)
│   ├── game.js
│   └── images/
└── user_data/      # 用户数据目录 (可读写)

/data/data/{packageName}/cache/migo/games/{gameId}/
└── tmp/            # 临时目录 (会话结束自动清理)
```

## SDK 核心类

| 类 | 说明 |
|---|------|
| `MigoRuntime` | SDK 入口（单例），设备检查、会话创建 |
| `GameSession` | 游戏会话，管理生命周期、输入、Surface |
| `RuntimeConfig` | 配置（Builder 模式），FPS/调试/签名等 |
| `MigoGameActivity` | 开箱即用的 Activity，一行代码启动游戏 |
| `MigoGameView` | 可嵌入的 FrameLayout，自动管理生命周期 |
| `GameSessionListener` | 事件回调接口 |
| `ErrorCode` | 错误码常量 |
| `DebugOverlayView` | 调试面板（debug 模式自动显示） |
| `SessionState` | 会话生命周期状态枚举 |
| `OnStateChangeListener` | 状态变更监听器 |
| `MigoException` | 结构化异常（含错误码、原因链、是否可恢复） |
| `PerformanceSnapshot` | 性能指标快照 |

## 许可证

MIT License
