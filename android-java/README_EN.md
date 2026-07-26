# Migo Android Demo

Android sample project for [Migo](https://github.com/minigame-labs/migo) — the open, high-performance, cross-engine native runtime for embedded HTML5 / mini-games, a WebView replacement built for games.

## Quick Start

### 1. Build Migo AAR

This demo currently depends on the local `../migo` build output:

- `../migo/platforms/android/dist/migo-debug.aar`

Build it first in the `migo` repo:

```bash
cd ../migo
bash scripts/build-aar.sh debug
```

If you want release AAR instead, build:

```bash
cd ../migo
bash scripts/build-aar.sh release
```

Then adjust the AAR path in `app/build.gradle.kts` if needed.

### 2. Prepare Game Files

Game files should be placed in the app's private directory with the following path format:

```
/data/data/com.minigame.androiddemo/files/migo/games/{gameId}/code/
├── game.js          # Game entry file
├── images/          # Image assets
├── workers/         # Worker scripts (if used)
└── ...              # Other resources
```

Where `{gameId}` is a unique game identifier (alphanumeric, underscore, hyphen, 1-64 characters).

Example: Push a `demo` game:

```bash
adb push your-game/ /data/data/com.minigame.androiddemo/files/migo/games/demo/code/
```

> Note: the SDK no longer auto-reads `game.json`.
> This demo now reads `code/game.json` on the host side and injects
> `workers` / `subPackages` / `deviceOrientation` (mapped to `startupOrientation`) into `RuntimeConfig`.
> You can also inject them manually:

```java
RuntimeConfig config = new RuntimeConfig.Builder(context)
    .setWorkersPath("workers")
    .setStartupOrientation("landscape")
    // .addSubPackage("stage1", "subpackages/stage1")
    .build();
```

### 3. Build and Run

Open the project in Android Studio, or build via command line:

```bash
./gradlew assembleDebug
adb install app/build/outputs/apk/debug/app-debug.apk
```

## Two Integration Approaches

The demo keeps only two official integration approaches:

### Approach 1: MigoGameActivity (Simplest)

Launch a game with one line of code. The SDK handles all lifecycle, Surface management, and touch events internally.

```java
import com.migo.runtime.MigoGameActivity;

// One-line launch
MigoGameActivity.launch(context, "demo", "game.js");

// Or with custom config
RuntimeConfig config = new RuntimeConfig.Builder(context)
    .setDebugEnabled(true)
    .build();
MigoGameActivity.launch(context, "demo", "game.js", config);
```

### Approach 2: MigoGameView (Embedded)

Embed the game as a View in any layout. Ideal when you need native UI elements around the game.

```java
import com.migo.runtime.MigoGameView;

MigoGameView gameView = new MigoGameView(context);

// Configure
RuntimeConfig config = new RuntimeConfig.Builder(context)
    .setDebugEnabled(true)
    .build();
gameView.setConfig(config);

// Set listener
gameView.setGameListener(listener);

// Add to layout
myLayout.addView(gameView);

// Load game
gameView.loadGame("demo", "game.js");

// Register handlers from session-created callback (before startGame)
gameView.setSessionCreatedListener(session -> {
    session.setAuthHandler(authHandler);
    session.setGameLogHandler(gameLogHandler);
    session.setSubpackageHandler(subpackageHandler);
});
```

## Event Handling

```java
import com.migo.runtime.callback.GameSessionListener;

session.setListener(new GameSessionListener() {
    @Override
    public void onGameReady() {
        // Game loaded and ready - hide loading screen
    }

    @Override
    public void onGameExit(int exitCode) {
        // Game exited, exitCode == 0 means normal exit
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

## Host Handlers (Latest API)

`GameSession` now supports these host callback handlers:

- `setAuthHandler(AuthHandler)`: handles `wx.login` / `wx.checkSession` / `wx.getUserInfo` / `wx.getPhoneNumber`
- `setGameLogHandler(GameLogHandler)`: receives game-reported logs (JSON)
- `setSubpackageHandler(SubpackageHandler)`: handles `loadSubpackage` / `preDownloadSubpackage`

Sample implementations in this demo:

- `app/src/main/java/com/minigame/androiddemo/auth/ProxyAuthHandler.java`
- `app/src/main/java/com/minigame/androiddemo/DemoGameLogHandler.java`
- `app/src/main/java/com/minigame/androiddemo/DemoSubpackageHandler.java`

### Auth Relay Quick Runbook

Relay client entry:

- `app/src/main/java/com/minigame/androiddemo/auth/ProxyAuthHandler.java`

Request contract:

- Endpoint: `POST {relayBaseUrl}/auth/request`
- Body: `{"action":"login|checkSession|getUserInfo|getPhoneNumber","params":{...},"gameId":"..."}`

Response contract:

- Success: `login/getPhoneNumber` -> `{"code":"..."}`, `checkSession` -> `{}`, `getUserInfo` -> `{"userInfo":...}`
- Failure: `{"error":"reason","errno":123}` (`errno` optional)

Demo integration points:

- `DebugMigoGameActivity` registers `ProxyAuthHandler` in `onSessionCreated(...)`
- `EmbeddedGameActivity` registers `ProxyAuthHandler` in `setSessionCreatedListener(...)`

URL setup:

- Emulator: `http://10.0.2.2:9527`
- Real device: `http://<YOUR_PC_LAN_IP>:9527`

Troubleshooting:

- Check `ProxyAuthHandler` and activity logs for callback flow
- Verify relay receives `/auth/request`
- Ensure `gameId` routing matches your desktop-side proxy instance

## New APIs

### Session State Listener

```java
session.setOnStateChangeListener((session, oldState, newState) -> {
    Log.d("Game", "State: " + oldState + " -> " + newState);
});

// Query current state
SessionState state = session.getState(); // CREATED, RUNNING, PAUSED, DESTROYED
```

### Performance Monitoring

```java
PerformanceSnapshot perf = session.getPerformanceSnapshot();
if (perf != null) {
    Log.d("Perf", "FPS=" + perf.fps + " frameTime=" + perf.frameTimeMs + "ms");
}
```

### Host ↔ JS Communication

```java
// Java → JS: execute JavaScript code
session.evaluateJavaScript("console.log('hello from host')");

// JS → Java: receive game messages
session.setMessageHandler((type, payload) -> {
    Log.d("Game", "Message: type=" + type + " payload=" + payload);
});
```

### Launch Failure Handling

Extend `MigoGameActivity` and override `onLaunchFailed`:

```java
@Override
protected void onLaunchFailed(int errorCode, String message) {
    Toast.makeText(this, "Launch failed: " + message, Toast.LENGTH_LONG).show();
    super.onLaunchFailed(errorCode, message); // default calls finish()
}
```

### Error Diagnostics

```java
MigoRuntime runtime = MigoRuntime.getInstance();
if (!runtime.isNativeLoaded()) {
    Throwable error = runtime.getNativeLoadError();
    Log.e("Init", "Native load failed", error);
}
```

## Project Structure

```
app/
└── src/main/
    ├── java/.../
    │   ├── MainActivity.java           # Demo selector
    │   ├── EmbeddedGameActivity.java   # Approach 2: MigoGameView embedding
    │   ├── DebugMigoGameActivity.java  # Approach 1: MigoGameActivity debug wrapper
    │   ├── GameConfigLoader.java       # Reads and parses code/game.json
    │   ├── RuntimeConfigCompat.java    # Injects game config into RuntimeConfig
    │   ├── DemoGameLogHandler.java     # GameLogHandler sample
    │   ├── DemoSubpackageHandler.java  # SubpackageHandler sample
    │   ├── auth/
    │   │   └── ProxyAuthHandler.java   # AuthHandler sample
    └── AndroidManifest.xml
```

## Game Directory Structure

```
/data/data/{packageName}/files/migo/games/{gameId}/
├── code/           # Game code directory (read-only)
│   ├── game.js
│   └── images/
└── user_data/      # User data directory (read-write)

/data/data/{packageName}/cache/migo/games/{gameId}/
└── tmp/            # Temporary directory (auto-cleaned on session close)
```

## Core SDK Classes

| Class | Description |
|-------|-------------|
| `MigoRuntime` | SDK entry point (singleton), device checks, session creation |
| `GameSession` | Game session, manages lifecycle, input, Surface |
| `RuntimeConfig` | Configuration (Builder pattern), FPS/debug/signing etc. |
| `MigoGameActivity` | Ready-to-use Activity, one-line game launch |
| `MigoGameView` | Embeddable FrameLayout, auto lifecycle management |
| `GameSessionListener` | Event callback interface |
| `ErrorCode` | Error code constants |
| `DebugOverlayView` | Debug overlay (auto-shown in debug mode) |
| `SessionState` | Session lifecycle state enum |
| `OnStateChangeListener` | State change listener |
| `MigoException` | Structured exception (error code, cause chain, recoverability) |
| `PerformanceSnapshot` | Performance metrics snapshot |

## License

MIT License
