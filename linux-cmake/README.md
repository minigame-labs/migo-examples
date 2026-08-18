> 中文: [README.zh-CN.md](README.zh-CN.md)

# Linux — C ABI via CMake

A host that embeds Migo in a window it owns, using `find_package(migo)` against
an installed SDK. Nothing here reaches into the Migo source tree.

## Run

```bash
bash run.sh
```

That resolves the Linux SDK into `sdk/`, builds with CMake, stages
[`../games/demo`](../games/), and runs it in an X11 window for 15 seconds.

Pass a different game or duration:

```bash
bash run.sh demo 30
bash run.sh /path/to/your-game 30
```

Not every directory under `../games/` runs here.
[`wx-adapter-demo`](../games/wx-adapter-demo/) is content written against `wx.*`
and needs the host to install an adapter as a prelude script; the C ABI this
example is built on has no way to do that, so it stops with `ReferenceError: wx
is not defined`. Its [README](../games/wx-adapter-demo/README.md) explains what
runs it and what C ABI hosts can do instead.

## Build only

```bash
bash ../scripts/resolve-migo-artifact.sh linux-sdk sdk
cmake -S . -B build -DCMAKE_PREFIX_PATH="$PWD/sdk"
cmake --build build
./build/migo-linux-example <files-dir> <game-id> <seconds>
```

`<files-dir>` is a directory whose content lives at
`<files-dir>/migo/games/<game-id>/code/`.

## Requirements

- CMake 3.16+, a C11 compiler
- Xlib development headers (`libx11-dev`)
- An X display (`DISPLAY` set)

## What the code shows

| Step | Where |
|---|---|
| Query what the linked library supports | `migo_query_capabilities` |
| Create engine and session | `migo_engine_create`, `migo_session_create` |
| Install host callbacks with your own dispatcher | `migo_session_set_host_callbacks` |
| Hand over a window you own | `MigoX11WindowDescriptor` + `migo_session_attach_surface` |
| Load content | `migo_session_load_content` |
| Feed input in CSS pixels | `migo_session_send_touch` |
| Detach and wait for release before destroying the window | `migo_surface_begin_detach` |

The engine never creates a window, never takes the main thread, and never calls
host code directly — it hands you a task and your dispatcher decides which
thread runs it.
