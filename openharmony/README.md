# OpenHarmony — C ABI via an ArkUI XComponent

A DevEco project that embeds Migo through its public C headers only, linking
`libmigo_capi.a` into its own native module (`libmigohost.so`). The surface is
an ArkUI `XComponent`: its `OnSurfaceCreated` callback hands over an
`OHNativeWindow*`, which is exactly what `MigoOpenHarmonyNativeWindowDescriptor`
carries — no translation, only ownership discipline. The host keeps its
reference, the engine takes its own, and the host must not destroy the window
until the release observer reports `RELEASED`.

## Run

```bash
bash run.sh            # x86_64, the DevEco emulator's architecture
bash run.sh aarch64     # real hardware
```

That resolves the Migo OpenHarmony SDK into `sdk-<arch>/`, stages it where the
native module's `CMakeLists.txt` expects it, builds the HAP with hvigor, and
installs and launches it on whatever device or emulator `hdc` sees. The bundled
content is [`../games/demo`](../games/), shipped inside the HAP as a rawfile —
it cannot be pushed there from outside, since the sandbox path is visible only
to this process and `hdc` runs as the unprivileged `shell` user. Shipping it
inside the package is also what a real application does.

### DevEco is on the Windows side

hvigor, the emulator and `hdc` all live inside a DevEco Studio install; the
engine and this repo are typically checked out in WSL. `run.sh` accounts for
two things that follow, both found by hitting them:

- **hvigor rejects a UNC project path** outright (`Invalid project path`), so
  the project can't be built in place on `\\wsl.localhost`. `run.sh` copies it
  to `C:\migo-ohos-example` (override with `MIGO_OHOS_WIN_DIR`) and builds
  there.
- **`cmd.exe` refuses a UNC working directory**, prints a warning, and falls
  back to `C:\Windows` — which then reads like a compile failure when nothing
  has been compiled yet. Every `cmd`/`hdc` invocation below runs from a local
  directory instead.

Set `DEVECO_HOME` if DevEco Studio isn't at the default
`C:\Program Files\Huawei\DevEco Studio`.

## Requirements

- DevEco Studio, with a target connected — a running emulator (Device Manager)
  or a real device over `hdc`. `hdc`, not `adb`: they are different protocols
  with different daemons, so an Android phone attached at the same time shows
  up in `adb` and not in `hdc`.
- WSL with `rsync` (or `cp`) and `wslpath`, if the repo lives there.

## What the code shows

| Step | Where |
|---|---|
| Create engine and session | `migo_engine_create`, `migo_session_create` |
| Install host callbacks with your own dispatcher | `migo_session_set_host_callbacks` |
| Hand over the XComponent's native window | `MigoOpenHarmonyNativeWindowDescriptor` + `migo_session_attach_surface` |
| Load content | `migo_session_load_content` |
| Feed every pointer from `OH_NativeXComponent_GetTouchEvent` | `migo_session_send_touch` |
| Detach and wait for release before the surface is destroyed | `migo_surface_begin_detach`, `migo_surface_release_query`, `migo_surface_release_destroy` |

The engine never creates a window, never takes ArkUI's main thread, and never
calls host code directly — it hands you a task and your dispatcher decides
which thread runs it. See `entry/src/main/cpp/napi_init.cpp`.
