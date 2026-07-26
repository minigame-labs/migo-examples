> 中文: [README.zh-CN.md](README.zh-CN.md)

# Migo Examples

Host integration examples for [Migo](https://github.com/minigame-labs/migo), a native
HTML5 / mini-game runtime.

Supported platforms:

| Directory | Host |
|---|---|
| [`android-java/`](android-java/) | Android, Java/Kotlin SDK |

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

## Licence

See [LICENSE](LICENSE).
