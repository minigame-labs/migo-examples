> English: [README.md](README.md)

# Linux — 经 CMake 使用 C ABI

一个把 Migo 嵌入自有窗口的宿主,通过 `find_package(migo)` 使用已安装的 SDK。
这里的代码不触碰 Migo 源码树。

## 运行

```bash
bash run.sh
```

它会把 Linux SDK 解析到 `sdk/`、用 CMake 构建、部署
[`../games/demo`](../games/),并在 X11 窗口里运行 15 秒。

指定其他游戏或时长:

```bash
bash run.sh demo 30
bash run.sh /path/to/your-game 30
```

## 仅构建

```bash
bash ../scripts/resolve-migo-artifact.sh linux-sdk sdk
cmake -S . -B build -DCMAKE_PREFIX_PATH="$PWD/sdk"
cmake --build build
./build/migo-linux-example <files-dir> <game-id> <seconds>
```

`<files-dir>` 是一个目录,内容位于 `<files-dir>/migo/games/<game-id>/code/`。

## 前置条件

- CMake 3.16+、C11 编译器
- Xlib 开发头文件(`libx11-dev`)
- 可用的 X display(已设 `DISPLAY`)

## 这份代码演示了什么

| 步骤 | 对应 API |
|---|---|
| 询问链接到的库支持什么 | `migo_query_capabilities` |
| 创建 engine 与 session | `migo_engine_create`、`migo_session_create` |
| 用自己的 dispatcher 安装宿主回调 | `migo_session_set_host_callbacks` |
| 交出自有窗口 | `MigoX11WindowDescriptor` + `migo_session_attach_surface` |
| 加载内容 | `migo_session_load_content` |
| 以 CSS 像素投喂输入 | `migo_session_send_touch` |
| 先 detach 并等待释放,再销毁窗口 | `migo_surface_begin_detach` |

引擎不创建窗口、不占用主线程,也从不直接调用宿主代码 —— 它把任务交给你,
由你的 dispatcher 决定在哪个线程运行。
