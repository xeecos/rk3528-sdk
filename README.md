# RK3528 SDK 构建脚本与文档

一套把 FriendlyELEC 官方 RK3528 编译流程**脚本化、可重复执行**的工具集。内容依据：

- [FriendlyELEC WiKi — Template:RK3528-BuildFromSource/zh](https://wiki.friendlyelec.com/wiki/index.php/Template:RK3528-BuildFromSource/zh)
- [friendlyarm/sd-fuse_rk3528 `kernel-6.1.y` README（中文）](https://github.com/friendlyarm/sd-fuse_rk3528/blob/kernel-6.1.y/README_cn.md)
- [friendlyarm/friendlywrt_manifests `master-v25.12/rk3528.xml`](https://github.com/friendlyarm/friendlywrt_manifests/blob/master-v25.12/rk3528.xml)
- [friendlyarm/prebuilts（11.3-aarch64 工具链）](https://github.com/friendlyarm/prebuilts)

> **本仓库不包含任何内核 / u-boot / FriendlyWrt 源码**，只提供统一入口脚本、配置、流程编排与中文文档；源码由脚本按需从上游拉取。
> 编译只在 **原生 Ubuntu x86_64** 或 **Windows 11 WSL2** 中支持，完整口径见 [§3 支持的平台](#3-支持的平台只支持这两个)。

---

## 1. 三条构建路线

| 路线 | 适用场景 | 入口命令 | 产出 |
|---|---|---|---|
| **A. FriendlyWrt 25.12 全量工程** | 要从零编译整套 OpenWrt/FriendlyWrt 系统 | `fw-init` → `fw-build all` | SD 镜像 + eMMC 卡刷镜像 |
| **B. 手工编译内核 / U-Boot** | 只想改内核配置、改 DTB、单独验证驱动 | `kernel-build` / `uboot-build` | `kernel.img`、`resource.img`、模块包、`uboot.img` 等 |
| **C. sd-fuse 脚本化编译与打包** | 基于官方分区镜像定制 Debian/Ubuntu 等系统 | `sdfuse-init` → `sdfuse-build` → `sdfuse-image` | SD 启动镜像 / SD-to-eMMC 卡刷镜像 |

三条路线互不冲突，共用 `workspace/` 下的源码，可按需组合。

---

## 2. 版本矩阵（来自 WiKi）

| 操作系统 | 内核 | U-Boot | 交叉编译器 | 分区 | 内核配置 |
|---|---|---|---|---|---|
| ubuntu-noble-core-arm64 | linux v6.1.y | v2017.09 | 11.3-aarch64 | GPT (`parameter.template`) | `nanopi5_linux_defconfig` |
| debian-trixie-core-arm64 | linux v6.1.y | v2017.09 | 11.3-aarch64 | GPT | `nanopi5_linux_defconfig` |
| openmediavault-arm64 | linux v6.1.y | v2017.09 | 11.3-aarch64 | GPT (`parameter-plain.txt`) | `nanopi5_linux_defconfig` |
| friendlywrt25 | linux v6.1.y | v2017.09 | 11.3-aarch64 | GPT | `nanopi5_linux_defconfig` + `friendlywrt.config` |
| friendlywrt25-docker | linux v6.1.y | v2017.09 | 11.3-aarch64 | GPT | 同上 |

- 内核源码：`friendlyarm/kernel-rockchip` 分支 `nanopi6-v6.1.y`
- U-Boot 源码：`friendlyarm/uboot-rockchip` 分支 `nanopi5-v2017.09`，板级目标 `nanopi_r3`
- 打包脚本：`friendlyarm/sd-fuse_rk3528` 分支 `kernel-6.1.y`
- 工具链路径：`/opt/FriendlyARM/toolchain/11.3-aarch64/bin/`

sd-fuse 另支持 `debian-bullseye-desktop-arm64`、`debian-bullseye-minimal-arm64`、`buildroot`、`friendlywrt24(-docker)`、`proxmox-arm64`、`eflasher`、`alpine-linux-arm64` 等目录名。

---

## 3. 支持的平台（只支持这两个）

| 平台 | 版本 | 状态 |
|---|---|---|
| **原生 Ubuntu x86_64** | 20.04 / 22.04 / 24.04 | 支持，官方基准环境 |
| **Windows 11 + WSL2 中的 Ubuntu** | 22.04（24.04 亦可） | 支持，见 [docs/09-WSL2构建指南.md](docs/09-WSL2构建指南.md) |

两个平台跑的是**同一套 x86_64 Linux 用户态**，官方全部预编译 ELF（工具链、`rkbin/tools/`、`sd-fuse tools/`）通用，无需任何架构分支。

**明确不作为支持目标**：WSL1（`check-host` 会直接拒绝）、macOS 原生、Apple Silicon / arm64 Linux 主机、Docker 作为独立平台、其它 Linux 发行版、Ubuntu 18.04（缺 `lz4`，脚本拦截）。这些环境**不测试、不修兼容性问题**。脚本里保留的架构检测、镜像变量、预演开关属于零维护成本的通用实现，不代表承诺支持。

### 环境要求

| 项目 | 要求 |
|---|---|
| 磁盘 | 全量 FriendlyWrt 编译建议 **≥ 60 GB** 空闲；仅编译内核约 20 GB |
| 内存 | 建议 ≥ 8 GB（全量编译推荐 12 GB+）；内存过小会导致打包进程被杀 |
| 权限 | 编译用普通用户；仅安装依赖、安装工具链、烧录 SD 卡时需要 `sudo` |
| 网络 | 需访问 GitHub 与 `downloads.friendlyelec.com`；国内可配置镜像 |
| WSL2 额外 | 源码必须放 WSL 原生 ext4（`/home/...`），不能放 `/mnt/*`；烧录回 Windows 侧 |

---

## 4. 快速开始

### 4.1 一次性环境准备

```bash
git clone <本仓库地址> rk3528-sdk && cd rk3528-sdk
chmod +x rk3528-sdk.sh scripts/*.sh

./rk3528-sdk.sh check-host --install       # 检查并 apt 安装编译依赖
./rk3528-sdk.sh install-toolchain          # 安装 11.3-aarch64 到 /opt/FriendlyARM/toolchain
./rk3528-sdk.sh status                     # 确认环境状态
```

> 源码与镜像默认放在 `./workspace`、`./downloads`。空间不够时先配置：
> `cp config/sdk.local.conf.example config/sdk.local.conf`，修改 `RK_WORKSPACE` 等路径。

### 4.2 路线 A：编译 FriendlyWrt 25.12

```bash
./rk3528-sdk.sh fw-init                    # repo init -b master-v25.12 -m rk3528.xml && repo sync
./rk3528-sdk.sh fw-build all               # ./build.sh rk3528.mk（u-boot+kernel+rootfs+sd-img）
./rk3528-sdk.sh fw-build emmc-img          # 额外生成 eMMC 卡刷固件

# docker 版：fw-build docker；改配置：fw-build menuconfig → fw-build rebuild
# 修改后重打包：fw-build sd-img / fw-build emmc-img
```

产物在 `workspace/friendlywrt25-rk3528/out/`。

### 4.3 路线 B：手工编译内核 / U-Boot

```bash
./rk3528-sdk.sh kernel-build                       # Linux 系统配置
./rk3528-sdk.sh kernel-build --friendlywrt        # FriendlyWrt 配置（追加 friendlywrt.config）
./rk3528-sdk.sh kernel-build --menuconfig         # 交互式改配置
./rk3528-sdk.sh uboot-build                       # ./make.sh nanopi_r3
```

产物在 `out/manual-kernel/`（`kernel.img`、`resource.img`、`kernel-modules-*.tar.gz`）与 `out/manual-uboot/`。

### 4.4 路线 C：sd-fuse 定制系统镜像

```bash
OS=ubuntu-noble-core-arm64
./rk3528-sdk.sh sdfuse-init "$OS" --with-eflasher   # 克隆 sd-fuse + 下载解压分区镜像
./rk3528-sdk.sh sdfuse-build kernel "$OS"           # 编译内核并自动更新 OS 目录
./rk3528-sdk.sh sdfuse-build uboot "$OS"            # 可选：编译 U-Boot
./rk3528-sdk.sh sdfuse-image sd "$OS"               # out/rk3528-sd-<OS>-6.1-arm64-YYYYMMDD.img
./rk3528-sdk.sh sdfuse-image emmc "$OS"             # out/rk3528-eflasher-<OS>-...img
```

若镜像包已在网盘下载到本地：`./rk3528-sdk.sh sdfuse-init "$OS" --images /path/to/ubuntu-noble-core-arm64-images.tgz`。

### 4.5 烧录 / 更新

```bash
# 在【开发板】上：更新 eMMC 分区（默认预演，确认后加 --execute）
sudo ./rk3528-sdk.sh install-board --device /dev/mmcblk2 \
     --img-dir /path/to/out/manual-kernel --execute

# 在【主机】上：开发板进入 loader 模式后线刷
sudo ./rk3528-sdk.sh flash-loader --img-dir /path/to/out/manual-kernel --execute

# 在【主机】上：把 SD 固件写入 SD 卡
./rk3528-sdk.sh sdfuse-image fuse "$OS" --device /dev/sdX
```

---

## 5. 目录结构

```
rk3528-sdk/
├── rk3528-sdk.sh              # 统一入口（子命令分发）
├── config/
│   ├── sdk.conf               # 默认配置（仓库/分支/路径/OS 列表）
│   └── sdk.local.conf.example # 本机配置模板（复制为 sdk.local.conf）
├── lib/
│   ├── common.sh              # 日志、检查、命令执行、下载、git 封装
│   └── config.sh              # 配置加载与派生路径
├── scripts/
│   ├── check-host.sh          # 主机环境检查 / 安装依赖
│   ├── install-toolchain.sh   # 安装 11.3-aarch64
│   ├── fw-init.sh             # FriendlyWrt repo init / sync
│   ├── fw-build.sh            # FriendlyWrt 全量与增量编译
│   ├── kernel-build.sh        # 手工编译内核 + 打包 kernel/resource
│   ├── uboot-build.sh         # 手工编译 u-boot
│   ├── sdfuse-init.sh         # sd-fuse 与分区镜像准备
│   ├── sdfuse-build.sh        # sd-fuse 编译内核/头文件/uboot
│   ├── sdfuse-image.sh        # 生成 SD / eMMC 镜像、烧写 SD 卡
│   ├── install-to-board.sh    # 目标板 dd 更新分区
│   ├── flash-loader.sh        # upgrade_tool 线刷
│   └── clean.sh               # 清理产物与日志
├── docs/                      # 中文文档（见下方索引）
├── workspace/                 # 源码（内容 gitignore）
├── downloads/                 # 下载的镜像与工具（内容 gitignore）
├── out/                       # 产物（内容 gitignore）
└── logs/                      # 构建日志（内容 gitignore）
```

**每个目录都带一份 `README.md`**：既说明该目录的职责，也让 Git 能够提交目录结构（Git 不追踪空目录）。
`workspace/`、`downloads/`、`out/`、`logs/` 采用 `目录/*` + `!目录/README.md` 的忽略规则 —— 占位文档入库，
源码、镜像、固件、日志等大文件仍一律不入库。

---

## 6. 配置

配置优先级：**环境变量 > `RK_CONF` 指定文件 > `config/sdk.local.conf` > `config/sdk.conf`**。

```bash
cp config/sdk.local.conf.example config/sdk.local.conf
# 编辑后用：./rk3528-sdk.sh config 查看生效值

# 临时覆盖示例
RK_JOBS=8 RK_WORKSPACE=/mnt/data/rk3528 ./rk3528-sdk.sh fw-build all
./rk3528-sdk.sh --conf ./my.conf fw-build all
```

常用变量：`RK_WORKSPACE`、`RK_DOWNLOAD_DIR`、`RK_OUTPUT_DIR`、`RK_JOBS`、`RK_DEFAULT_OS`、
`RK_TOOLCHAIN_BIN`、`RK_MIN_FREE_GB`、`RK_GITHUB_MIRROR`、`RK_RAW_MIRROR`、`RK_DRY_RUN`。

**预演模式**：`./rk3528-sdk.sh --dry-run <命令>` 只打印将要执行的命令，不下载、不编译、不写入，适合先核对流程。

---

## 7. 命令速查

| 命令 | 作用 |
|---|---|
| `help` / `config` / `status` | 帮助 / 生效配置 / 工作区状态 |
| `check-host [--install]` | 检查（安装）主机依赖 |
| `install-toolchain [--package FILE]` | 安装交叉编译器 |
| `fw-init [--force]` | 拉取 FriendlyWrt 25.12 源码 |
| `fw-build all\|docker\|uboot\|kernel\|friendlywrt\|sd-img\|emmc-img` | 全量 / 单组件 / 打包 |
| `fw-build menuconfig\|rebuild\|single\|clean\|cleanall` | 改配置 / 二次编译 / 单线程排错 / 清理 |
| `kernel-build [--friendlywrt] [--menuconfig] [--pack-only]` | 手工编译内核与打包 |
| `uboot-build [--no-clone]` | 手工编译 U-Boot |
| `sdfuse-init [OS] [--images FILE\|URL] [--with-eflasher]` | 准备 sd-fuse 工作区 |
| `sdfuse-build kernel\|headers\|uboot [OS]` | 用 sd-fuse 编译 |
| `sdfuse-image sd\|emmc\|fuse [OS]` | 生成 / 烧写固件 |
| `install-board --device DEV --execute` | 目标板 dd 更新分区 |
| `flash-loader --img-dir DIR --execute` | 线刷 |
| `clean [images\|logs\|all]` | 清理产物 |

完整参数见 [docs/06-命令参考.md](docs/06-命令参考.md)。

---

## 8. 安全约定

- 所有 `dd`、SD 卡烧写、线刷命令**默认只打印计划**；必须显式加 `--execute`（或 `fuse` 动作）才会写入。
- 危险操作要求**手工输入设备名 / `LOADER` 确认串**，`--yes` 不能跳过。
- `install-board` 会检查镜像是否超过分区容量，并在写入前把原分区备份到 `out/partition-backup-<时间戳>/`。
- `clean` 只删除本工具生成的文件，绝不动 `workspace/` 下的源码。

---

## 9. 文档索引

| 文档 | 内容 |
|---|---|
| [docs/00-快速开始.md](docs/00-快速开始.md) | 三种典型场景的完整命令序列 |
| [docs/01-构建环境.md](docs/01-构建环境.md) | 主机要求、依赖包、工具链、配置与目录 |
| [docs/02-FriendlyWrt编译.md](docs/02-FriendlyWrt编译.md) | 路线 A 全流程与 build.sh 目标说明 |
| [docs/03-内核与U-Boot编译.md](docs/03-内核与U-Boot编译.md) | 路线 B 内核/模块/资源镜像打包 |
| [docs/04-sd-fuse打包.md](docs/04-sd-fuse打包.md) | 路线 C 分区镜像、环境变量、固件打包 |
| [docs/05-烧录与更新.md](docs/05-烧录与更新.md) | GPT 分区布局、dd 更新、线刷、SD 烧写 |
| [docs/06-命令参考.md](docs/06-命令参考.md) | 全部命令、参数、环境变量 |
| [docs/07-故障排查.md](docs/07-故障排查.md) | 常见错误与处理 |
| [docs/08-Wiki流程对照.md](docs/08-Wiki流程对照.md) | 官方 Wiki 每条命令 → 本工具命令逐条对应 |
| [docs/09-WSL2构建指南.md](docs/09-WSL2构建指南.md) | Windows / WSL2 完整落地步骤（含磁盘规划与烧录注意事项） |

---

## 10. 许可

本仓库脚本与文档沿用仓库根目录的 [MIT LICENSE](LICENSE)。
上游源码、镜像与工具遵循 FriendlyELEC / 各上游仓库各自的许可，请自行遵守。
