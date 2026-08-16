> English: [README.md](README.md)

# Android — Java/Kotlin SDK

## 构建

```bash
# 在仓库根目录执行
bash scripts/resolve-migo-artifact.sh android-aar android-java/libs/migo.aar
cd android-java
./gradlew :app:assembleDebug
```

APK 产物路径为 `app/build/outputs/apk/debug/app-debug.apk`。

## 运行

以下命令面向单个已连接的设备或模拟器;如果连接了多个,请给 `adb` 加上
`-s <serial>`。

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
bash scripts/push-game.sh
adb shell am start -n com.minigame.androiddemo/.MainActivity
```

`scripts/push-game.sh` 会把一个游戏部署到 app 的私有存储目录下,game id 等于
该游戏目录的目录名。`GAME` 可以是一个裸名称(在 [`../games/`](../games/) 下
解析),也可以是仓库之外任意游戏目录的路径;默认值为 `demo`:

```bash
bash scripts/push-game.sh demo
```

一个游戏目录包含 `game.js`(入口文件)和 `game.json`。

## 集成方式

| 类 | 使用位置 |
|---|---|
| `MigoGameActivity` | `app/src/main/java/com/minigame/androiddemo/DebugMigoGameActivity.java` |
| `MigoGameView` | `app/src/main/java/com/minigame/androiddemo/EmbeddedGameActivity.java` |

### 方式三：适配层注入（未修改的 wx 形态内容）

`MainActivity` 的第三个按钮跑的是 [`games/wx-adapter-demo/game.js`](../games/wx-adapter-demo/game.js)——
一字未改，直接调用 `wx.createCanvas()`、`wx.onTouchStart()` 等，文件里没有任何
`migo.*`。Migo 引擎本身只装载 `migo.*`；`wx` 是在启动时通过注入
[migo-wx-adapter](https://github.com/minigame-labs/migo-wx-adapter) 的 IIFE
bundle 作为 boot prelude script 提供的：

```java
String adapterSource = readAsset("migo-wx-adapter.bundle.js"); // app/src/main/assets/
RuntimeConfig config = new RuntimeConfig.Builder(this)
        .addPreludeScript("migo-wx-adapter.bundle.js", adapterSource)
        .build();
DebugMigoGameActivity.launch(this, "wx-adapter-demo", "game.js", config);
```

`app/src/main/assets/migo-wx-adapter.bundle.js` 是已构建并提交的适配层产物
（在 `migo-wx-adapter` 的 checkout 里跑 `npm run build`，再把
`dist/migo-wx-adapter.bundle.js` 拷过来）——Android 构建流程里没有接 Node
工具链，没法现场构建。用它自己的 game id 单独部署这份内容：

```bash
bash scripts/push-game.sh wx-adapter-demo
```

这才是真实集成会用到的形态：一个游戏中心分发未经修改的第三方小游戏包时，
是按内容期望的形态注入对应适配层，而不是把每个游戏手工搬到 `migo.*` 上。

不使用上述两个封装类、直接调用 `GameSession` / `MigoRuntime` 的独立示例位于
[`snippets/`](snippets/):`MinimalActivity.java`、`GameActivity.java`、
`KotlinGameActivity.kt`。构建方式:

```bash
./gradlew :snippets:assembleDebug
```
