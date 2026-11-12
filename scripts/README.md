# scripts/

**支持平台**：原生 Ubuntu 20.04/22.04/24.04 **x86_64** 与 Win11 **WSL2** 中的 Ubuntu
（见根 README §3 与 `docs/09-WSL2构建指南.md`）。所有脚本开头都会 `source ../lib/config.sh`
并调用 `require_linux`，WSL1 / 非 Linux 会被统一拒绝；非 x86_64 / 非 Ubuntu 只警告不硬拦。

具体执行脚本。推荐通过仓库根目录的统一入口调用：

```bash
./rk3528-sdk.sh help
./rk3528-sdk.sh <命令> [参数...]
```

也可独立运行（脚本会自行加载 `../lib/config.sh`）：

```bash
bash scripts/fw-build.sh all
./scripts/sdfuse-image.sh sd ubuntu-noble-core-arm64
```

## 脚本清单

| 脚本 | 入口命令 | 作用 |
|---|---|---|
| `check-host.sh` | `check-host [--install]` | 检查系统/依赖/磁盘/工具链，`--install` 用 apt 补齐 |
| `install-toolchain.sh` | `install-toolchain` | 安装 11.3-aarch64 交叉编译器 |
| `fw-init.sh` | `fw-init` | FriendlyWrt 25.12 `repo init` + `repo sync` |
| `fw-build.sh` | `fw-build <target>` | 全量/单组件/打包/二次编译/单线程排错 |
| `kernel-build.sh` | `kernel-build` | 手工编译内核、模块，打包 kernel.img / resource.img |
| `uboot-build.sh` | `uboot-build` | 手工编译 u-boot 并收集产物 |
| `sdfuse-init.sh` | `sdfuse-init` | 克隆 sd-fuse、下载解压分区镜像 |
| `sdfuse-build.sh` | `sdfuse-build` | 用 sd-fuse 编译内核 / 头文件 / u-boot |
| `sdfuse-image.sh` | `sdfuse-image` | 生成 SD / eMMC 固件，或烧写 SD 卡 |
| `install-to-board.sh` | `install-board` | 在目标板上 dd 更新 GPT 分区 |
| `flash-loader.sh` | `flash-loader` | 主机线刷（upgrade_tool v2+） |
| `clean.sh` | `clean [images\|logs\|all]` | 清理本工具产物与日志 |

入口脚本中的命令名与文件名不完全一致（例如 `install-board` → `install-to-board.sh`），映射表在 `rk3528-sdk.sh` 的 `_SCRIPTS` 数组中。

## 编写约定

- 开头 `source .../lib/config.sh`，统一 `set -euo pipefail`，并调用 `require_linux`。
- 平台判断统一走 `lib/common.sh` 的 `detect_platform()`，不要在子脚本里各自实现。
- 命令执行统一走 `run` / `run_in` / `run_in_logged`，以自动支持 `--dry-run` 与日志。
- 涉及 `dd`、`fusing.sh`、`upgrade_tool` 的脚本默认**只打印计划**，`--execute` 才写入，并调用 `confirm_dangerous`。
- 参数解析用 `while + case`，未知参数直接报错，不要静默忽略。

完整参数见 [docs/06-命令参考.md](../docs/06-命令参考.md)。
