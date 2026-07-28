> English: [README.md](README.md)

# Migo Examples

[Migo](https://github.com/minigame-labs/migo)(原生 HTML5 / 小游戏运行时)的宿主集成示例仓库。

已支持的平台:

| 目录 | 宿主 |
|---|---|
| [`android-java/`](android-java/) | Android, Java/Kotlin SDK |
| [`linux-cmake/`](linux-cmake/) | Linux,经 CMake 使用 C ABI |

游戏内容位于 [`games/`](games/),每个游戏一个目录。一个游戏目录包含
`game.js`(入口文件)和 `game.json`。所有宿主示例按名称运行同一份内容。

## 运行时版本

所有示例都基于 [`migo-version.txt`](migo-version.txt) 中指定的 Migo release 构建。

## 获取运行时

```bash
bash scripts/resolve-migo-artifact.sh android-aar android-java/libs/migo.aar
```

此命令从 `migo-version.txt` 指定的 release 中下载 `android-aar` 平台对应的资产,
并在写入目标路径前,将其与该 release 发布的 attestation 进行校验。

若要改用本地 Migo 检出而非 release:

```bash
MIGO_LOCAL_REPO=/path/to/migo \
  bash scripts/resolve-migo-artifact.sh android-aar android-java/libs/migo.aar
```

本地模式从该检出中解析 `platforms/android/dist/migo-<profile>-debug.aar`,
它由以下命令在该检出中构建:

```bash
bash scripts/build-aar.sh debug --product-profile <profile>
```

`resolve-migo-artifact.sh` 读取的环境变量:

| 变量 | 作用 |
|---|---|
| `MIGO_LOCAL_REPO` | 本地 Migo 检出路径;设置后切换到本地模式。 |
| `MIGO_PROFILE` | 两种模式下都生效的产品 profile(默认 `full`)。 |
| `GITHUB_TOKEN` | 默认模式下,随 GitHub API/下载请求发送的 bearer token。 |

`android-aar` 是目前唯一支持的平台取值。

## 许可证

见 [LICENSE](LICENSE)。
