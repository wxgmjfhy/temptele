# 3D Agent Docker 复现

使用 Ubuntu 24.04、Blender 4.5.16 LTS、CadQuery 2.8.0、Godot 4.7.2 和 OpenCode 2.2.7，从锁定的上游依赖构建环境并生成验证产物。

## 环境要求

- Linux amd64，或 Windows 上启用了 Linux Docker 容器的 x86-64 WSL2。
- Docker Engine 和 Buildx，`default` 构建器可用。准备、构建和验证使用同一 Docker daemon。
- Bash、GNU coreutils 和 curl。首次准备需访问 Docker Hub、Ubuntu Snapshot、PyPI 文件服务器及工具发布站点。
- 下载约需 1.08 GiB 的存储空间，镜像和构建缓存另外占用 Docker 数据盘。WSL 用户应检查 Docker 数据盘所在的 Windows 分区。

## 构建和验证

在本目录运行。

```bash
bash prepare.sh
bash build.sh
bash smoke/run.sh "$PWD/results-rebuild"
```

`prepare.sh` 下载固定版本的依赖并校验，按摘要拉取 Ubuntu 基础镜像。依赖下载完成后，构建和测试的容器均禁用外网。已下载且校验通过的包可供重试时复用。 [Ubuntu Snapshot](https://snapshot.ubuntu.com/) · [Docker 镜像摘要](https://docs.docker.com/reference/cli/docker/image/pull/#pull-an-image-by-digest-immutable-identifier)

`build.sh` 校验准备好的输入，默认构建 `agent3d-smoke:all` 和 `agent3d-smoke:godot-preview`。测试脚本要求输出目录是尚不存在的新目录。

| 测试 | 验证内容 | 生成的文件 |
| --- | --- | --- |
| Blender | Cycles CPU 渲染，导出带贴图 GLB 并重读 Blender 文件 | `blender.png`、`asset.glb`、`asset.blend` |
| CadQuery | 导出并重读 STEP，核验实体尺寸和体积 | `plate.step`、`plate.stl` |
| Godot | 导入 Blender 的 GLB，核验纹理、尺寸、物理射线和软件渲染像素 | `godot.png`、`godot.log`、`godot-preview.log` |
| OpenCode | 使用本地模拟模型读取 PNG 附件，调用 shell 运行 Blender 并保存事件轨迹 | `harness/events.jsonl`、`harness/session.json`、`harness/asset.glb` |

测试使用 Linux 容器、CPU 渲染和模拟模型。生成真实模型的轨迹时，模型端点与认证配置由运行方提供。
