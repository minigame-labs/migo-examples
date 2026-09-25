> 中文: [README.zh-CN.md](README.zh-CN.md)

# iOS and macOS — Swift, `MigoGameView`

An iOS app and a macOS app that run [`../games/demo`](../games/) through the
Apple SDK's product surface: install the game package, load it into a
`MigoGameView`. The two apps share the code that does that
([`Shared/ExampleGame.swift`](Shared/ExampleGame.swift)); they differ only in
the window that holds the view.

## Run

```bash
bash run.sh macos
bash run.sh ios-simulator
```

That resolves the Apple SDK into `sdk/`, builds with `xcodebuild`, and runs
the game -- on macOS in a window, on iOS in an iPhone simulator. Pass a number
of seconds to quit after that long; the exit status then says whether the game
became ready and was given frames:

```bash
bash run.sh macos 10
```

Or open `MigoExample.xcodeproj` in Xcode after resolving the SDK once:

```bash
bash ../scripts/resolve-migo-artifact.sh apple-sdk sdk
open MigoExample.xcodeproj
```

To run on an iPhone, select the `MigoExample-iOS` target and set your team
under *Signing & Capabilities*.

## Requirements

- Xcode 16 or later
- iOS 15.2 or later; a Mac with macOS 11 or later

## What the project shows

| Step | Where |
|---|---|
| Link one product per platform | the `Migo` local package (`sdk/`): `MigoApplePerformancePlus` for iOS, `MigoMacV8` for macOS |
| Install the game the app ships, once per build | `MigoGameInstaller.install` in `ExampleGame.makeView` |
| Run it and follow what it does | `MigoGameView.loadGame`, `onEvent` in `ExampleGame.run` |
| Lock the iOS app to the game's orientation | `GameViewController.supportedInterfaceOrientations` and the target's orientation settings |
| Allow V8's JIT on macOS | `macOS/MigoExample.entitlements` (`com.apple.security.cs.allow-jit`) with the hardened runtime |
| Embed ANGLE in the macOS app before it is signed | the macOS target's *Embed ANGLE* build phase |

iOS needs nothing embedded by hand: the SDK declares ANGLE as framework
dependencies and Xcode embeds them. On macOS ANGLE is a pair of dylibs, which
the build phase copies into `Contents/Frameworks` and signs with the app's
identity; the target's runpath includes `@executable_path/../Frameworks`.

The game is installed `.unsigned` because it ships inside this signed app.
Games an app downloads should be signed and installed with
`.verified(publicKey:)`; the SDK's README describes the package format.

[`wx-adapter-demo`](../games/wx-adapter-demo/) does not run here: it is written
against `wx.*`, which `MigoGameView` does not install.
