> 中文: [README.zh-CN.md](README.zh-CN.md)

# Windows — C ABI via CMake

A host that embeds Migo in a window it owns, using `find_package(migo)` against
an installed SDK. Nothing here reaches into the Migo source tree.

## Run

```bash
bash run.sh
```

That resolves the Windows SDK into `sdk/`, builds with MSVC, stages
[`../games/demo`](../games/), and runs it in a Win32 window for 15 seconds.

Pass a different game or duration:

```bash
bash run.sh demo 30
bash run.sh /path/to/your-game 30
```

`run.sh` drives the build from WSL and runs it on Windows. To work entirely on
Windows, use the build-only steps below.

## Build only

```cmd
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=%CD%\sdk
cmake --build build
build\migo-windows-example.exe <files-dir> <game-id> <seconds>
```

`<files-dir>` is a directory whose content lives at
`<files-dir>\migo\games\<game-id>\code\`.

## Requirements

- CMake 3.16+, Visual Studio Build Tools (MSVC), Ninja
- The SDK's `bin/` directory beside the executable. `CMakeLists.txt` copies it
  as a post-build step: `migo.dll` imports V8 from `rusty_v8.dll` and resolves
  EGL through the ANGLE DLLs, all by name at load time. A missing one fails
  before `main` runs, with no output.

## What the code shows

| Step | Where |
|---|---|
| Query what the linked library supports | `migo_query_capabilities` |
| Create engine and session | `migo_engine_create`, `migo_session_create` |
| Install host callbacks with your own dispatcher | `migo_session_set_host_callbacks` |
| Hand over a window you own | `MigoWin32HwndDescriptor` + `migo_session_attach_surface` |
| Load content | `migo_session_load_content` |
| Feed input in CSS pixels | `migo_session_send_touch` |
| Detach and wait for release before destroying the window | `migo_surface_begin_detach` |

The engine never creates a window, never owns the message loop, and never calls
host code directly — it hands you a task and your dispatcher decides which
thread runs it.
