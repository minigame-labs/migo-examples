> 中文: [README.zh-CN.md](README.zh-CN.md)

# Migo Examples

Host integration examples for [Migo](https://github.com/minigame-labs/migo), a native
HTML5 / mini-game runtime.

Supported platforms:

| Directory | Host |
|---|---|
| [`android-java/`](android-java/) | Android, Java/Kotlin SDK |
| [`linux-cmake/`](linux-cmake/) | Linux, C ABI through CMake |

Game content lives in [`games/`](games/), one directory per game. A game
directory holds `game.js` (entry point) and `game.json`. Every host example
runs the same content by name.

## Runtime version

Every example builds against the Migo release named in
[`migo-version.txt`](migo-version.txt).

## Getting the runtime

```bash
bash scripts/resolve-migo-artifact.sh android-aar android-java/libs/migo.aar
```

This downloads the release asset for the `android-aar` platform from the
release named in `migo-version.txt`, then verifies it against that release's
published attestation before writing it to the destination path.

To build against a local Migo checkout instead of a release:

```bash
MIGO_LOCAL_REPO=/path/to/migo \
  bash scripts/resolve-migo-artifact.sh android-aar android-java/libs/migo.aar
```

Local mode resolves `platforms/android/dist/migo-<profile>-debug.aar` from
that checkout, built there with:

```bash
bash scripts/build-aar.sh debug --product-profile <profile>
```

Environment variables read by `resolve-migo-artifact.sh`:

| Variable | Effect |
|---|---|
| `MIGO_LOCAL_REPO` | Path to a local Migo checkout; switches to local mode. |
| `MIGO_PROFILE` | Product profile to resolve, in both modes (default `full`). |
| `GITHUB_TOKEN` | Bearer token sent on GitHub API/download requests in default mode. |

`android-aar` is the only supported platform value.

## Android without Gradle (NDK / C ABI)

The `android-java/` example uses the Java/Kotlin SDK. To embed Migo from native
code instead, the same release publishes a C ABI package per ABI:

```bash
curl -fsSLO https://github.com/minigame-labs/migo/releases/download/v0.9.0/migo-sdk-android-arm64-v8a.tar.gz
tar xzf migo-sdk-android-arm64-v8a.tar.gz
```

Its `README.md` carries the two CMake flags an NDK consumer must pass; without
them the build fails with errors that point somewhere other than the cause.

## Licence

See [LICENSE](LICENSE).
