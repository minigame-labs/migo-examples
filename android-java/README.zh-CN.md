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

不使用上述两个封装类、直接调用 `GameSession` / `MigoRuntime` 的独立示例位于
[`snippets/`](snippets/):`MinimalActivity.java`、`GameActivity.java`、
`KotlinGameActivity.kt`。构建方式:

```bash
./gradlew :snippets:assembleDebug
```
