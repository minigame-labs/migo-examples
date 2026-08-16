> 中文: [README.zh-CN.md](README.zh-CN.md)

# Migo Examples

Host integration examples for [Migo](https://github.com/minigame-labs/migo), a native
HTML5 / mini-game runtime.

Supported platforms:

| Directory | Host |
|---|---|
| [`android-java/`](android-java/) | Android, Java/Kotlin SDK |
| [`linux-cmake/`](linux-cmake/) | Linux, C ABI through CMake |
| [`windows-cmake/`](windows-cmake/) | Windows, C ABI through CMake |
| [`openharmony/`](openharmony/) | OpenHarmony, C ABI through an ArkUI XComponent |

Game content lives in [`games/`](games/), one directory per game. A game
directory holds `game.js` (entry point) and `game.json`. Every host example
runs the same content by name.

## Runtime version

Each platform is pinned to its own release, because Migo publishes them
separately:

| Platform value | Pin file |
|---|---|
| `android-aar` | [`migo-version.txt`](migo-version.txt) |
| `linux-sdk` | [`migo-linux-version.txt`](migo-linux-version.txt) |
| `windows-sdk` | [`migo-windows-version.txt`](migo-windows-version.txt) |
| `ohos-sdk` | [`migo-ohos-version.txt`](migo-ohos-version.txt) |

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
| `MIGO_ARCH` | Architecture to resolve, for `linux-sdk`, `windows-sdk` and `ohos-sdk` (default `x86_64`); ignored by `android-aar`. |
| `GITHUB_TOKEN` | Bearer token sent on GitHub API/download requests in default mode. |

Platform values are `android-aar`, `linux-sdk`, `windows-sdk` and `ohos-sdk`.
The three SDK kinds each ship one tarball per architecture rather than a
universal package, which is what `MIGO_ARCH` selects between; `android-aar`
ignores it, since the AAR is multi-ABI and Gradle picks the right `.so` per
device. The destination differs by platform: `android-aar` writes a single
`.aar` file, while the three SDK kinds unpack into a prefix directory that
`find_package(migo)` reads.

## Android without Gradle (NDK / C ABI)

The `android-java/` example uses the Java/Kotlin SDK. To embed Migo from native
code instead, the same release publishes a C ABI package per ABI:

```bash
# Replace v0.9.2 with the tag you want -- see the releases page for what's current.
curl -fsSLO https://github.com/minigame-labs/migo/releases/download/v0.9.2/migo-0.9.2-capi-android-arm64.tar.gz
tar xzf migo-0.9.2-capi-android-arm64.tar.gz
```

Its `README.md` carries the two CMake flags an NDK consumer must pass; without
them the build fails with errors that point somewhere other than the cause.

## Contact

- Commercial licensing: licensing@minigame-labs.com
- Security reports: see [SECURITY.md](SECURITY.md)

## Licence

See [LICENSE](LICENSE).
