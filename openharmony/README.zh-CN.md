> English: [README.md](README.md)

# OpenHarmony — 经 ArkUI XComponent 使用 C ABI

一个只通过公开 C 头文件嵌入 Migo 的 DevEco 工程,把 `libmigo_capi.a` 链接进自己的
原生模块(`libmigohost.so`)。承载画面的是一个 ArkUI `XComponent`:它的
`OnSurfaceCreated` 回调交出一个 `OHNativeWindow*`,这正是
`MigoOpenHarmonyNativeWindowDescriptor` 所携带的 —— 不需要转换,只需要遵守所有权
约定。宿主保留自己的引用,引擎持有自己的引用,宿主在 release observer 报告
`RELEASED` 之前不能销毁窗口。

## 运行

```bash
bash run.sh            # x86_64,DevEco 模拟器的架构
bash run.sh aarch64     # 真机
```

这会把 Migo OpenHarmony SDK 解析到 `sdk-<arch>/`、部署到原生模块
`CMakeLists.txt` 期望的位置、用 hvigor 构建 HAP,再在 `hdc` 能看到的设备或
模拟器上安装并启动。内置的内容是 [`../games/demo`](../games/),作为 rawfile
打进 HAP —— 它无法从外部推送进去,因为沙箱路径只对本进程可见,而 `hdc` 是以
无特权的 `shell` 用户运行的。打进包里也正是真实应用会做的事。

### DevEco 在 Windows 一侧

hvigor、模拟器和 `hdc` 都在 DevEco Studio 安装目录里;引擎和本仓库通常检出在
WSL 里。`run.sh` 处理了由此而来的两件事,都是踩过坑才知道的:

- **hvigor 直接拒绝 UNC 工程路径**(`Invalid project path`),所以工程不能
  原地在 `\\wsl.localhost` 上构建。`run.sh` 把它拷贝到 `C:\migo-ohos-example`
  (可用 `MIGO_OHOS_WIN_DIR` 覆盖)再构建。
- **`cmd.exe` 拒绝 UNC 工作目录**,会打印警告并回退到 `C:\Windows`——在还
  没编译任何东西时,这读起来就像编译失败。因此下面每一次 `cmd`/`hdc` 调用
  都从本地目录发起。

如果 DevEco Studio 不在默认的 `C:\Program Files\Huawei\DevEco Studio`,
设置 `DEVECO_HOME`。

## 依赖

- DevEco Studio,并连接了一个目标 —— 正在运行的模拟器(Device Manager)或
  经 `hdc` 连接的真机。是 `hdc`,不是 `adb`:二者协议和守护进程都不同,
  同时接着一台 Android 手机只会出现在 `adb` 里,不会出现在 `hdc` 里。
- WSL 下需要 `rsync`(或 `cp`)和 `wslpath`,如果仓库检出在那里的话。

## 代码演示了什么

| 步骤 | 位置 |
|---|---|
| 询问链接到的库支持什么 | `migo_query_capabilities` |
| 创建 engine 与 session | `migo_engine_create`、`migo_session_create` |
| 用自己的 dispatcher 安装宿主回调 | `migo_session_set_host_callbacks` |
| 交出 XComponent 的原生窗口 | `MigoOpenHarmonyNativeWindowDescriptor` + `migo_session_attach_surface` |
| 加载内容 | `migo_session_load_content` |
| 把 `OH_NativeXComponent_GetTouchEvent` 里的每个触点都喂进去 | `migo_session_send_touch` |
| 先 detach 并等待释放,再让 surface 被销毁 | `migo_surface_begin_detach`、`migo_surface_release_query`、`migo_surface_release_destroy` |

引擎不创建窗口、不占有 ArkUI 的主线程、也不直接调用宿主代码 —— 它交给你一个
任务,由你的 dispatcher 决定在哪个线程运行。见
`entry/src/main/cpp/napi_init.cpp`。
