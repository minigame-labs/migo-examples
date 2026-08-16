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

### Option 3: adapter injection (unmodified wx-shaped content)

`MainActivity`'s third button runs [`games/wx-adapter-demo/game.js`](../games/wx-adapter-demo/game.js)
unmodified — it calls `wx.createCanvas()`, `wx.onTouchStart()`, and so on directly,
with no `migo.*` anywhere in the file. Migo itself only ever installs `migo.*`;
`wx` is supplied at boot by injecting the
[migo-wx-adapter](https://github.com/minigame-labs/migo-wx-adapter) IIFE bundle
as a prelude script:

```java
String adapterSource = readAsset("migo-wx-adapter.bundle.js"); // app/src/main/assets/
RuntimeConfig config = new RuntimeConfig.Builder(this)
        .addPreludeScript("migo-wx-adapter.bundle.js", adapterSource)
        .build();
DebugMigoGameActivity.launch(this, "wx-adapter-demo", "game.js", config);
```

`app/src/main/assets/migo-wx-adapter.bundle.js` is a committed build of that
adapter (`npm run build` in a `migo-wx-adapter` checkout, then copy
`dist/migo-wx-adapter.bundle.js` here) — the Android build has no Node
toolchain wired in to build it on the fly. Deploy the demo content the same
way as `demo`, under its own game id:

```bash
bash scripts/push-game.sh wx-adapter-demo
```

This is the shape a real integration takes: a game centre distributing
third-party mini-game packages unmodified injects the adapter that matches
what the content expects, rather than porting every title to `migo.*` by hand.

Standalone snippets demonstrating direct `GameSession` / `MigoRuntime`
integration, without either wrapper class, live in
[`snippets/`](snippets/): `MinimalActivity.java`, `GameActivity.java`, and
`KotlinGameActivity.kt`. Build them with:

```bash
./gradlew :snippets:assembleDebug
```
