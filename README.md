# RK3528 SDK

Rockchip RK3528（四核 Cortex-A53, arm64）的构建工具集，提供**两种使用方式**：

| 方式 | 特点 | 入口 |
|---|---|---|
| **脚本化路线** | 四条构建路线（FriendlyWrt / 手工内核 / sd-fuse / W132D），按需拉取上游源码 | `./rk3528-sdk.sh <子命令>` |
| **Docker 一键构建** | 宿主机只需 Docker，无需本机工具链；容器内完成 U-Boot + 内核 + Buildroot | `make all` |

两种方式互不干扰，可按需选择。

内容依据：

- [FriendlyELEC WiKi — Template:RK3528-BuildFromSource/zh](https://wiki.friendlyelec.com/wiki/index.php/Template:RK3528-BuildFromSource/zh)
- [friendlyarm/sd-fuse_rk3528 `kernel-6.1.y` README（中文）](https://github.com/friendlyarm/sd-fuse_rk3528/blob/kernel-6.1.y/README_cn.md)
- [friendlyarm/friendlywrt_manifests `master-v25.12/rk3528.xml`](https://github.com/friendlyarm/friendlywrt_manifests/blob/master-v25.12/rk3528.xml)
- [friendlyarm/prebuilts（11.3-aarch64 工具链）](https://github.com/friendlyarm/prebuilts)
- [Building a Rockchip RK3528 Linux Image from Scratch](https://medium.com/@yangxin.sz.ch/building-a-rockchip-rk3528-linux-image-from-scratch-no-sdk-required-a4ba2d658a61)

> **本仓库不包含任何内核 / u-boot / FriendlyWrt 源码**，只提供统一入口脚本、配置、流程编排与中文文档；源码由脚本按需从上游拉取。

---

## 1. 构建路线

| 路线 | 适用场景 | 入口命令 | 产出 |
|---|---|---|---|
| **A. FriendlyWrt 25.12 全量工程** | 要从零编译整套 OpenWrt/FriendlyWrt 系统 | `fw-init` → `fw-build all` | SD 镜像 + eMMC 卡刷镜像 |
| **B. 手工编译内核 / U-Boot** | 只想改内核配置、改 DTB、单独验证驱动 | `kernel-build` / `uboot-build` | `kernel.img`、`resource.img`、模块包、`uboot.img` 等 |
| **C. sd-fuse 脚本化编译与打包** | 基于官方分区镜像定制 Debian/Ubuntu 等系统 | `sdfuse-init` → `sdfuse-build` → `sdfuse-image` | SD 启动镜像 / SD-to-eMMC 卡刷镜像 |
| **D. ZTE W132D 主线 Linux** | 同 SoC 的另一台设备：主线内核 + Armbian | `w132d init` → `w132d fetch` → `w132d build` / `w132d flash` | `w132d.img`、Armbian deb 包、USB 刷写包 |
| **E. Docker 一键构建** | 宿主机零工具链，Buildroot 根文件系统 | `make all` | `sdcard.img`、`boot.img`、`rootfs.ext4` |

A/B/C 互不冲突，共用 `workspace/` 下的 FriendlyELEC 源码。
**路线 D 是独立上游、独立固件体系**（主线内核 + U-Boot + Armbian GPT），与 A/B/C
**不共用内核、U-Boot、分区镜像，产物不可混刷**，详见 [docs/10-W132D主线Linux.md](docs/10-W132D主线Linux.md)。
路线 E 使用 Docker 容器隔离，源码与产物存放在 Docker 卷中，详见 [§4.2](#42-方式二docker-一键构建)。

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

**路线 E（Docker）已验证的源码版本**：

| 组件 | 仓库 / 分支 | 说明 |
|---|---|---|
| Linux 6.1 BSP | `radxa/kernel @ linux-6.1-stan-rkr5` | 含 `rockchip_linux_defconfig`、rk3528 全套设备树、`scripts/resource_tool.c` |
| U-Boot 2024.03 | `radxa/u-boot @ next-dev-v2024.03` | 含 `configs/rk3528_defconfig` |
| rkbin | `rockchip-linux/rkbin` | BL31 v1.21 / DDR v1.14 / SPL v1.07（自动取最新） |
| Buildroot | `buildroot/buildroot @ 2025.02.x` | 上游 LTS，glibc 工具链 |

---

## 3. 支持的平台

| 平台 | 版本 | 状态 |
|---|---|---|
| **原生 Ubuntu x86_64** | 20.04 / 22.04 / 24.04 | 支持，官方基准环境 |
| **Windows 11 + WSL2 中的 Ubuntu** | 22.04（24.04 亦可） | 支持，见 [docs/09-WSL2构建指南.md](docs/09-WSL2构建指南.md) |
| **macOS / Windows + Docker Desktop** | 任意 | 路线 E 支持（源码与产物在 Docker 卷内，规避大小写不敏感） |

两个脚本化平台跑的是**同一套 x86_64 Linux 用户态**，官方全部预编译 ELF（工具链、`rkbin/tools/`、`sd-fuse tools/`）通用，无需任何架构分支。

> 路线 D（W132D 主线 Linux）额外要求 Docker，因为上游 Armbian 构建框架运行在容器中。
> 这是**构建工具依赖**，不是新增受支持平台；主机支持矩阵不变。

**脚本化路线的明确不支持目标**：WSL1（`check-host` 会直接拒绝）、macOS 原生、Apple Silicon / arm64 Linux 主机、Docker 作为独立平台、其它 Linux 发行版、Ubuntu 18.04（缺 `lz4`，脚本拦截）。这些环境**不测试、不修兼容性问题**。
（路线 E 通过 Docker 容器运行，不受此限制。）

### 环境要求

| 项目 | 要求 |
|---|---|
| 磁盘 | 全量 FriendlyWrt 编译建议 **≥ 60 GB** 空闲；仅编译内核约 20 GB；路线 E 约 20 GB |
| 内存 | 建议 ≥ 8 GB（全量编译推荐 12 GB+）；内存过小会导致打包进程被杀 |
| 权限 | 编译用普通用户；仅安装依赖、安装工具链、烧录 SD 卡时需要 `sudo` |
| 网络 | 需访问 GitHub 与 `downloads.friendlyelec.com`；国内可配置镜像 |
| WSL2 额外 | 源码必须放 WSL 原生 ext4（`/home/...`），不能放 `/mnt/*`；烧录回 Windows 侧 |

---

## 4. 快速开始

### 4.1 方式一：脚本化

```bash
git clone <本仓库地址> rk3528-sdk && cd rk3528-sdk
chmod +x rk3528-sdk.sh scripts/*.sh

./rk3528-sdk.sh check-host --install       # 检查并 apt 安装编译依赖
./rk3528-sdk.sh install-toolchain          # 安装 11.3-aarch64 到 /opt/FriendlyARM/toolchain
./rk3528-sdk.sh status                     # 确认环境状态
```

> 源码与镜像默认放在 `./workspace`、`./downloads`。空间不够时先配置：
> `cp config/sdk.local.conf.example config/sdk.local.conf`，修改 `RK_WORKSPACE` 等路径。

**路线 A：编译 FriendlyWrt 25.12**

```bash
./rk3528-sdk.sh fw-init                    # repo init -b master-v25.12 -m rk3528.xml && repo sync
./rk3528-sdk.sh fw-build all               # ./build.sh rk3528.mk（u-boot+kernel+rootfs+sd-img）
./rk3528-sdk.sh fw-build emmc-img          # 额外生成 eMMC 卡刷固件

# docker 版：fw-build docker；改配置：fw-build menuconfig → fw-build rebuild
# 修改后重打包：fw-build sd-img / fw-build emmc-img
```

产物在 `workspace/friendlywrt25-rk3528/out/`。

**路线 B：手工编译内核 / U-Boot**

```bash
./rk3528-sdk.sh kernel-build                       # Linux 系统配置
./rk3528-sdk.sh kernel-build --friendlywrt        # FriendlyWrt 配置（追加 friendlywrt.config）
./rk3528-sdk.sh kernel-build --menuconfig         # 交互式改配置
./rk3528-sdk.sh uboot-build                       # ./make.sh nanopi_r3
```

产物在 `out/manual-kernel/`（`kernel.img`、`resource.img`、`kernel-modules-*.tar.gz`）与 `out/manual-uboot/`。

**路线 C：sd-fuse 定制系统镜像**

```bash
OS=ubuntu-noble-core-arm64
./rk3528-sdk.sh sdfuse-init "$OS" --with-eflasher   # 克隆 sd-fuse + 下载解压分区镜像
./rk3528-sdk.sh sdfuse-build kernel "$OS"           # 编译内核并自动更新 OS 目录
./rk3528-sdk.sh sdfuse-build uboot "$OS"            # 可选：编译 U-Boot
./rk3528-sdk.sh sdfuse-image sd "$OS"               # out/rk3528-sd-<OS>-6.1-arm64-YYYYMMDD.img
./rk3528-sdk.sh sdfuse-image emmc "$OS"             # out/rk3528-eflasher-<OS>-...img
```

若镜像包已在网盘下载到本地：`./rk3528-sdk.sh sdfuse-init "$OS" --images /path/to/ubuntu-noble-core-arm64-images.tgz`。

**路线 D：W132D 主线 Linux**

```bash
./rk3528-sdk.sh w132d init                  # clone 上游（需 Docker / Python 3.12+ / 35 GiB）
./rk3528-sdk.sh w132d fetch --download      # 锁定 Linux v7.2.x + Armbian + U-Boot
./rk3528-sdk.sh w132d build image           # 产出 w132d.img
./rk3528-sdk.sh w132d status

# 或跳过本地构建，直接刷官方 Release（不需要 Docker）
./rk3528-sdk.sh w132d flash                 # 下载 + SHA256 校验 + 只读自检
./rk3528-sdk.sh w132d flash --execute       # 高危：USB 整盘刷写
```

> W132D 用 `rkdeveloptool` 走 USB 整盘刷写，**不能**用路线 A/B/C 的 `dd` / `upgrade_tool` / `fusing.sh`。
> WSL2 的 USB 直通与上游 Windows 路径均未获实机验证，刷写建议用原生 Ubuntu 物理机。

> **W132D 在非原厂系统上的启动问题（GPIO 电源域 / eMMC vqmmc / 模块 oops）已完整定位并修复**，
> 详见 [docs/w132d-compatibility.md](docs/w132d-compatibility.md)。

### 4.2 方式二：Docker 一键构建

宿主机只需安装 Docker，无需任何本机工具链：

```bash
make all          # 拉源码 + 完整构建（首次约 1~2 小时，含源码下载）
ls -lh images/
#   idbloader.img   DDR init + SPL（rkbin）
#   u-boot.itb      U-Boot + BL31
#   boot.img        内核 Image + 设备树（resource 格式）
#   rootfs.ext4     Buildroot 根文件系统
#   sdcard.img      整卡镜像（GPT），直接写入 SD 卡
#   flash.sh        烧写助手
```

烧写到 SD 卡（Linux `/dev/sdX`，macOS 先 `diskutil list` 查设备号）：

```bash
sudo bash images/flash.sh sd /dev/sdX
```

网络慢或需要代理时（容器内自动把 `127.0.0.1` 改写为 `host.docker.internal`）：

```bash
RK_PROXY=http://127.0.0.1:7890 make all
```

串口参数 **1500000 8N1**（RK3528 调试串口 UART0），默认登录 `root / root`。

**Docker 方式常用命令**

| 命令 | 说明 |
|---|---|
| `make image` | 仅构建 Docker 编译镜像 `rk3528-build:v1` |
| `make shell` | 进入编译容器交互 shell（手工实验用） |
| `make smoke` | 工具链冒烟测试：交叉编译 `apps/hello/hello.c` 并校验产物架构 |
| `make fetch` | 拉取四份源码（浅克隆） |
| `make uboot` / `make kernel` / `make rootfs` | 单独构建某一组件 |
| `make pack` | 重新打包，产物导出到项目根目录 `images/` |
| `make menuconfig` | 内核 menuconfig（改完 `make kernel` 生效） |
| `make uboot-menuconfig` | U-Boot menuconfig |
| `make info` | 打印当前配置（仓库 / 分支 / DTB / 工具链） |
| `make clean` | 清理编译产物，保留源码 |
| `make distclean` | 删除 `src/`、`out/`（保留 `dl/` 下载缓存） |

### 4.3 烧录 / 更新（脚本化路线）

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
├── rk3528-sdk.sh              # 脚本化路线统一入口（子命令分发）
├── Makefile                   # Docker 路线宿主机入口
├── build.sh                   # 容器内构建编排器（make 的实际执行者）
├── env.sh                     # Docker 路线全部构建配置（仓库、分支、defconfig、DTB、分区…）
├── config/
│   ├── sdk.conf               # 脚本化默认配置（仓库/分支/路径/OS 列表）
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
│   ├── w132d.sh               # 路线 D：W132D 主线 Linux 编排
│   ├── docker.sh              # Docker 封装（UID 映射、ccache 卷、环境透传）
│   ├── fetch.sh               # 源码拉取
│   ├── build-uboot.sh         # U-Boot + idbloader
│   ├── build-kernel.sh        # 内核 + 模块 + resource_tool
│   ├── build-rootfs.sh        # Buildroot rootfs
│   ├── pack.sh                # boot.img / sdcard.img / flash.sh 打包
│   ├── smoke.sh               # 工具链冒烟测试
│   └── clean.sh               # 清理产物与日志
├── docker/Dockerfile          # Docker 编译环境（Ubuntu 22.04 + 全部依赖）
├── docker-compose.yml         # 可选的 compose 用法
├── configs/
│   └── rk3528_buildroot_defconfig
├── overlays/rootfs/           # 叠加进 rootfs 的 /etc 配置（fstab、网络、modprobe…）
├── apps/hello/                # 应用层交叉编译示例（hello.c + Makefile）
├── docs/                      # 中文文档（见 §10 索引）
├── workspace/                 # 脚本化路线源码（内容 gitignore）
├── downloads/                 # 下载的镜像与工具（内容 gitignore）
├── images/                    # Docker 路线最终交付镜像（pack 后生成）
├── src/                       # Docker 路线源码（Docker 卷 rk3528-src）
├── out/                       # 构建中间产物（Docker 卷 rk3528-out）
├── dl/                        # Buildroot 下载缓存
└── logs/                      # 构建日志（内容 gitignore）
```

**每个目录都带一份 `README.md`**：既说明该目录的职责，也让 Git 能够提交目录结构（Git 不追踪空目录）。
`workspace/`、`downloads/`、`out/`、`logs/` 采用 `目录/*` + `!目录/README.md` 的忽略规则 —— 占位文档入库，
源码、镜像、固件、日志等大文件仍一律不入库。

> **为什么 Docker 路线的 `src/` 和 `out/` 放在 Docker 卷里？**
> Linux 内核源码包含大小写同名文件（如 `xt_dscp.c` 与 `XT_DSCP.c`），
> macOS/Windows 文件系统不区分大小写，直接 bind mount 会静默丢文件导致编译失败。
> 因此源码与编译产物存放在 Docker 卷（Linux 文件系统、大小写敏感，速度也更快），
> 浏览源码请用 `make shell`；最终镜像由 `make pack` 导出到 `images/`。

---

## 6. 配置

### 6.1 脚本化路线

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

### 6.2 Docker 路线（env.sh）

所有变量均可被环境变量覆盖，例如换板型：

```bash
RK_KERNEL_DTB=rk3528-evb3-lp4x-v10 make kernel pack
```

常用板型设备树（`src/kernel/arch/arm64/boot/dts/rockchip/`）：

| DTB | 板型 |
|---|---|
| `rk3528-evb1-ddr4-v10-linux` | Rockchip EVB1 DDR4（默认） |
| `rk3528-evb1-ddr4-v10-spi-nand-linux` | EVB1 + SPI NAND |
| `rk3528-evb2-ddr3-v10` / `rk3528-evb3-lp4x-v10` / `rk3528-evb4-ddr4-v10` | 其他 EVB |
| `rk3528-demo1-lp4-v10` / `rk3528-demo4-ddr4-v10-linux` / `rk3528-demo6-ddr3-v10` | DEMO 板 |

其他关键配置：

- `RK_CROSS_COMPILE`：交叉前缀。容器为 arm64（Apple Silicon）时留空原生编译；
  x86 宿主机默认 `aarch64-linux-gnu-`。可指向自备工具链（如 Rockchip GCC 11.3）。
- `KERNEL_CMDLINE`：内建命令行。默认
  `console=ttyFIQ0,1500000 console=ttyS0,1500000 earlycon=uart8250,mmio32,0xff9f0000 root=/dev/mmcblk0p3 rootwait rw`
  —— root 分区对应 `sdcard.img` 的 GPT 第 3 分区；SD 卡设备号非 `mmcblk0` 时请覆盖。
- `BL31_BIN` / `DDR_BIN` / `SPL_BIN`：rkbin 固件文件名，默认自动选最新版本。
- `SDCARD_SIZE`：整卡镜像大小，默认 `2G`（rootfs 变大后可改 `4G` 等）。
- `JOBS`：并行任务数，默认取容器 CPU 数。

---

## 7. 启动链（Docker 路线产出对应关系）

```
Boot ROM
  └─ idbloader.img  @0x40    rkbin DDR init + SPL（tools/mkimage -T rksd 打包）
       └─ u-boot.itb @0x4000  U-Boot 2024.03 + BL31（rkbin）
            └─ boot.img  @0x8000  resource 格式：内核 Image + 设备树
                 └─ rootfs     @0x40000 Buildroot ext4
```

镜像内分区布局（512B 扇区，RK3528 标准偏移）：

| 分区 | 起始扇区 | 内容 |
|---|---|---|
| （无分区表项） | 0x40 / 64 | idbloader.img |
| uboot | 0x4000 / 16384 | u-boot.itb |
| boot | 0x8000 / 32768 | boot.img |
| rootfs | 0x40000 / 262144 | rootfs.ext4 |

---

## 8. 工具链说明

- Docker 镜像在 **amd64** 宿主机上使用 `gcc-aarch64-linux-gnu-` 交叉编译；
  在 **arm64** 宿主机（Apple Silicon Docker Desktop）上容器本身就是 aarch64，
  直接原生编译，速度最快。两种方式产出的内核/U-Boot 完全一致。
- Buildroot 根文件系统使用其内部 glibc 工具链（独立于上述工具链）。
- `ccache` 通过独立 Docker 卷 `rk3528-ccache` 持久化，重复构建明显加速。
- 应用程序交叉编译示例见 `apps/hello/`（`make shell` 进入容器后 `cd apps/hello && make`）。
- 脚本化路线使用 FriendlyELEC 预编译的 **11.3-aarch64** 工具链，安装到 `/opt/FriendlyARM/toolchain/`。

---

## 9. 烧写方式

1. **SD 卡（推荐）**：`sudo bash out/images/flash.sh sd /dev/sdX` —— 写入带 GPT 的整卡镜像。
2. **eMMC / MASKROM**：设备进入 MASKROM（或 Loader）模式后
   `sudo bash out/images/flash.sh usb`（需已安装 `rkdeveloptool`）。
   注意：此方式按裸偏移写入、不含 GPT，`root=` 需与实际设备号匹配；完整量产
   刷机建议使用 Rockchip `upgrade_tool` + `update.img`。
3. 调试串口：UART0（`0xff9f0000`），**1500000 8N1**，波特率不符时无任何输出。

---

## 10. 命令速查（脚本化路线）

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
| `w132d init\|fetch\|build\|verify\|flash\|status` | 路线 D：W132D 主线 Linux（详见 `w132d help`） |
| `clean [images\|logs\|all]` | 清理产物 |

完整参数见 [docs/06-命令参考.md](docs/06-命令参考.md)。

---

## 11. 安全约定

- 所有 `dd`、SD 卡烧写、线刷命令**默认只打印计划**；必须显式加 `--execute`（或 `fuse` 动作）才会写入。
- 危险操作要求**手工输入设备名 / `LOADER` 确认串**，`--yes` 不能跳过。
- `install-board` 会检查镜像是否超过分区容量，并在写入前把原分区备份到 `out/partition-backup-<时间戳>/`。
- `clean` 只删除本工具生成的文件，绝不动 `workspace/` 下的源码。

---

## 12. 常见问题

- **首次 `make all` 很慢**：需要克隆源码（内核浅克隆约几百 MB）并构建 Buildroot
  工具链，属正常现象；之后增量构建只需几分钟。
- **macOS 上编译偏慢**：源码与编译目录已位于 Docker 卷（虚拟机本地盘），如仍慢
  可确认 Docker Desktop 分配了足够 CPU/内存。
- **烧写后无串口输出**：确认波特率为 1500000；确认 USB 串口适配器接的是
  板上调试串口；`flash.sh usb` 裸写方式请确认 `root=` 与实际存储设备一致。
- **rootfs 换软件包**：编辑 `configs/rk3528_buildroot_defconfig`（或
  `make shell` 后 `make -C src/buildroot O=$PWD/out/buildroot menuconfig`），
  再 `make rootfs && make pack`。
- **换分支/换源**：改 `env.sh` 中 `*_REPO` / `*_BRANCH` 后删除对应 `src/` 子目录，
  重新 `make fetch`。
- **W132D 上系统起不来（黑屏 / 无网络 / CPU 挂起）**：见
  [docs/w132d-compatibility.md](docs/w132d-compatibility.md)，其中记录了 GPIO 电源域、
  eMMC `vqmmc-supply` 缺失、`clk_ignore_unused` 与模块黑名单四类问题的完整解法。

---

## 13. 文档索引

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
| [docs/10-W132D主线Linux.md](docs/10-W132D主线Linux.md) | 路线 D：ZTE W132D 主线内核 + Armbian，与 BSP 的边界、构建与 USB 刷写 |
| [docs/w132d-compatibility.md](docs/w132d-compatibility.md) | W132D 板级兼容性修复：GPIO 电源域、eMMC vqmmc、clk_ignore_unused、模块黑名单 |

---

## 14. 许可

本仓库脚本与文档沿用仓库根目录的 [MIT LICENSE](LICENSE)。
上游源码、镜像与工具遵循 FriendlyELEC / 各上游仓库各自的许可，请自行遵守。
