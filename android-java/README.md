> 中文: [README.zh-CN.md](README.zh-CN.md)

# Android — Java/Kotlin SDK

## Build

```bash
# from the repository root
bash scripts/resolve-migo-artifact.sh android-aar android-java/libs/migo.aar
cd android-java
./gradlew :app:assembleDebug
```

The APK is written to `app/build/outputs/apk/debug/app-debug.apk`.

## Run

The commands below target a single attached device or emulator; pass
`adb -s <serial>` if more than one is attached.

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
bash scripts/push-game.sh
adb shell am start -n com.minigame.androiddemo/.MainActivity
```

`scripts/push-game.sh` deploys a game into the app's private storage, under a
game id equal to the game directory's name. `GAME` may be a bare name
(resolved under [`../games/`](../games/)) or a path to any game directory
outside the repository; it defaults to `demo`:

```bash
bash scripts/push-game.sh demo
```

A game directory holds `game.js` (entry point) and `game.json`.

## Integration approaches

| Class | Used by |
|---|---|
| `MigoGameActivity` | `app/src/main/java/com/minigame/androiddemo/DebugMigoGameActivity.java` |
| `MigoGameView` | `app/src/main/java/com/minigame/androiddemo/EmbeddedGameActivity.java` |

Standalone snippets demonstrating direct `GameSession` / `MigoRuntime`
integration, without either wrapper class, live in
[`snippets/`](snippets/): `MinimalActivity.java`, `GameActivity.java`, and
`KotlinGameActivity.kt`. Build them with:

```bash
./gradlew :snippets:assembleDebug
```
