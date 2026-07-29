> English: [README.md](README.md)

# Windows — 经 CMake 使用 C ABI

一个把 Migo 嵌入自有窗口的宿主,通过 `find_package(migo)` 使用已安装的 SDK。
这里的代码不触碰 Migo 源码树。

## 运行

```bash
bash run.sh
```

它会把 Windows SDK 解析到 `sdk/`、用 MSVC 构建、部署
[`../games/demo`](../games/),并在 Win32 窗口里运行 15 秒。

指定其他游戏或时长:

```bash
bash run.sh demo 30
bash run.sh /path/to/your-game 30
```

`run.sh` 从 WSL 驱动构建、在 Windows 上运行。若完全在 Windows 上工作,
使用下面的仅构建步骤。

## 仅构建

```cmd
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=%CD%\sdk
cmake --build build
build\migo-windows-example.exe <files-dir> <game-id> <seconds>
```

`<files-dir>` 是一个目录,内容位于
`<files-dir>\migo\games\<game-id>\code\`。

## 依赖

- CMake 3.16+、Visual Studio Build Tools (MSVC)、Ninja
- SDK 的 `bin/` 目录需与可执行文件同级。`CMakeLists.txt` 在构建后拷贝它:
  `migo.dll` 从 `rusty_v8.dll` 导入 V8,并经 ANGLE 的 DLL 解析 EGL,
  全部在加载期按名解析。缺任何一个都会在 `main` 之前失败,且没有任何输出。

## 代码演示了什么

| 步骤 | 位置 |
|---|---|
| 询问链接到的库支持什么 | `migo_query_capabilities` |
| 创建 engine 与 session | `migo_engine_create`、`migo_session_create` |
| 用自己的 dispatcher 安装宿主回调 | `migo_session_set_host_callbacks` |
| 交出自己拥有的窗口 | `MigoWin32HwndDescriptor` + `migo_session_attach_surface` |
| 加载内容 | `migo_session_load_content` |
| 以 CSS 像素喂入输入 | `migo_session_send_touch` |
| 先 detach 并等待释放,再销毁窗口 | `migo_surface_begin_detach` |

引擎不创建窗口、不占有消息循环、也不直接调用宿主代码 —— 它交给你一个任务,
由你的 dispatcher 决定在哪个线程运行。
