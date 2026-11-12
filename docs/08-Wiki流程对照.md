# 08 · 官方 Wiki 流程与本工具逐条对照

来源：[FriendlyELEC WiKi — Template:RK3528-BuildFromSource/zh](https://wiki.friendlyelec.com/wiki/index.php/Template:RK3528-BuildFromSource/zh)
辅助：[sd-fuse_rk3528 `kernel-6.1.y` README_cn.md](https://github.com/friendlyarm/sd-fuse_rk3528/blob/kernel-6.1.y/README_cn.md)

本文用于核对「脚本没有偏离官方流程」，也方便在脚本不适用时直接照抄官方命令。

---

## 1 编译 Openwrt/Friendlywrt

### 1.1 下载 FriendlyWrt 25.12 源代码

**Wiki**

```bash
mkdir friendlywrt25-rk3528
cd friendlywrt25-rk3528
git clone https://github.com/friendlyarm/repo --depth 1 tools
tools/repo init -u https://github.com/friendlyarm/friendlywrt_manifests -b master-v25.12 \
        -m rk3528.xml --repo-url=https://github.com/friendlyarm/repo --no-clone-bundle
tools/repo sync -c --no-clone-bundle
```

**本工具**：`./rk3528-sdk.sh fw-init`

差异：源码放到 `workspace/friendlywrt25-rk3528`；`repo sync` 增加 `-j4`（`--jobs` 可调）；已初始化时跳过 `repo init` 以便续传；所有 URL/分支由 `config/sdk.conf` 集中配置。

### 1.2 首次编译

| Wiki | 本工具 |
|---|---|
| `./build.sh rk3528.mk` | `fw-build all` |
| `./build.sh rk3528-docker.mk` | `fw-build docker` |
| `(cd friendlywrt && make -j1 V=s)` | `fw-build single` |
| `(cd friendlywrt && rm -rf tmp/go-build && make -j1 V=s)` | `fw-build single --docker` |
| `./build.sh emmc-img` | `fw-build emmc-img` |
| `./build.sh sd-img` | `fw-build sd-img` |

差异：增加 `tee` 日志、磁盘空间检查、root 检查、参数校验；`--no-log` 可关日志。

### 1.3 二次编译

**Wiki**

```bash
cd friendlywrt
make menuconfig      # 改动 FriendlyWrt 的配置
rm -rf ./tmp
make -j${nproc}
cd ../
./build.sh sd-img
./build.sh emmc-img
```

**本工具**

```bash
./rk3528-sdk.sh fw-build menuconfig
./rk3528-sdk.sh fw-build rebuild
```

差异：`make -j${nproc}` 是 Wiki 笔误，改用真实 `nproc`（`RK_JOBS` 可覆盖）；删 `friendlywrt/tmp` 前会列出路径并要求确认，选 N 则跳过清理直接增量编译。

### 1.4 ~ 1.6 单独编译

| Wiki | 本工具 |
|---|---|
| `./build.sh uboot` | `fw-build uboot` |
| `./build.sh kernel` | `fw-build kernel` |
| `./build.sh friendlywrt` | `fw-build friendlywrt` |
| `(cd friendlywrt && make -j1 V=s)` | `fw-build single` |

补充：`build.sh` 还支持 `all`、`u-boot`（别名）、`clean`、`cleanall`，本工具分别映射为 `fw-build clean` / `fw-build cleanall`。

---

## 2 其他 Linux 系统编译

### 2.1 各 OS 对应的内核与 U-Boot 版本

| 操作系统 | 内核 | U-Boot | 编译器 | 分区 | 内核配置 |
|---|---|---|---|---|---|
| openmediavault-arm64 | linux v6.1.y | v2017.09 | 11.3-aarch64 | GPT `parameter-plain.txt` | `nanopi5_linux_defconfig` |
| ubuntu-noble-core-arm64 | linux v6.1.y | v2017.09 | 11.3-aarch64 | GPT `parameter.template` | `nanopi5_linux_defconfig` |
| debian-trixie-core-arm64 | linux v6.1.y | v2017.09 | 11.3-aarch64 | GPT | `nanopi5_linux_defconfig` |
| friendlywrt25 | linux v6.1.y | v2017.09 | 11.3-aarch64 | GPT | `nanopi5_linux_defconfig` + `friendlywrt.config` |
| friendlywrt25-docker | linux v6.1.y | v2017.09 | 11.3-aarch64 | GPT | 同上 |

- 内核仓库 `friendlyarm/kernel-rockchip`，分支 `nanopi6-v6.1.y`
- U-Boot 仓库 `friendlyarm/uboot-rockchip`，分支 `nanopi5-v2017.09`，配置 `nanopi5_defconfig`，构建目标 `nanopi_r3`
- 工具链 `export PATH=/opt/FriendlyARM/toolchain/11.3-aarch64/bin/:$PATH`

本工具把这些全部写进 `config/sdk.conf`，由 `setup_toolchain_path` 自动导出。

### 2.2 编译内核 linux-v6.1.y

**Wiki**：clone → `touch .scmversion` → `make ... nanopi5_linux_defconfig` → `make -j$(nproc)` → modules / modules_install / depmod / strip → 下载 `mkkrnlimg`、`resource_tool`、两张 logo → 生成 `kernel.img`、`resource.img`。

**本工具**：`./rk3528-sdk.sh kernel-build`（`--friendlywrt` 对应 option2，`--menuconfig` 对应配置界面，`--pack-only` 只重打包）。

差异详见 [03-内核与U-Boot编译.md](03-内核与U-Boot编译.md#1-编译内核-linux-v61y)：脚本用 `print0/xargs -0 -r`、自动找 depmod、缓存打包工具到 `downloads/tools/`、产物集中到 `out/manual-kernel/` 并额外生成模块 tar 包。

### 2.3 编译 u-boot v2017.09

| Wiki | 本工具 |
|---|---|
| `git clone .../rkbin -b friendlyelec` | `uboot-build` 自动 clone（分支 `RK_RKBIN_BRANCH`） |
| `git clone .../uboot-rockchip -b nanopi5-v2017.09` | 同上 |
| `export PATH=...` | `setup_toolchain_path` |
| `cd uboot-rockchip && ./make.sh nanopi_r3` | 同上，并记录日志 |
| 手工收集 `uboot.img` / `trust.img` / `rk356x_spl_loader_*.bin` | 自动收集，loader 改名为 `MiniLoaderAll.bin` |

约束不变：`rkbin` 与 `uboot-rockchip` 必须同级。

### 2.4.1 安装到目标板

**Wiki**

```bash
parted /dev/mmcblk2 print
dd if=resource.img of=/dev/mmcblk2p5 bs=1M
dd if=kernel.img  of=/dev/mmcblk2p6 bs=1M
dd if=uboot.img   of=/dev/mmcblk2p1 bs=1M
# 更新驱动模块：替换 /lib/modules
```

**本工具**

```bash
sudo ./rk3528-sdk.sh install-board --device /dev/mmcblk2 \
     --img-dir /path/to/out/manual-kernel --execute
```

差异：默认预演；优先按 `PARTLABEL` 分区名定位（读不到才回退 1/2/5/6）；校验镜像不超分区容量；写入前备份原分区；写入前手工输入设备名确认；写完 `sync`。

### 2.4.2 打包新的 SD Image

**Wiki**：指向 `sd-fuse_rk3528/kernel-6.1.y`，说明其用途（分区镜像制作、合并单一镜像、一键编译并更新 rootfs 中的模块）。

**本工具**：`sdfuse-init` → `sdfuse-build` → `sdfuse-image sd`，见 [04-sd-fuse打包.md](04-sd-fuse打包.md)。

### 2.4.3 线刷（Linux 系统）

**Wiki**

```bash
sudo reboot loader                       # 在开发板上
sudo upgrade_tool di -k  kernel.img
sudo upgrade_tool di -re resource.img
sudo upgrade_tool di -u  uboot.img
sudo upgrade_tool RD
```

**本工具**

```bash
sudo ./rk3528-sdk.sh flash-loader --img-dir /path/to/out/manual-kernel --execute
```

差异：默认预演并打印前置检查清单；自动查找 `upgrade_tool`（`--tool` 可指定）；写入前输入 `LOADER` 确认；`--no-reboot` 可跳过 `RD`。工具仍需 v2 以上版本，Wiki 用 v2.30。

---

## 3 使用脚本进行编译

### 3.1 下载工具与固件

| Wiki | 本工具 |
|---|---|
| `git clone https://github.com/friendlyarm/sd-fuse_rk3528.git -b kernel-6.1.y` | `sdfuse-init <OS>` |
| `tar xvzf /path/to/netdrive/03_分区镜像文件/ubuntu-noble-core-arm64-images.tgz` | 同上（自动从官方服务器下载，或 `--images` 指定本地/URL） |

Wiki 这里写「以 friendlycore-focal 系统为例」，但实际解压的是 `ubuntu-noble-core-arm64-images.tgz`，属文案遗留；本工具以实际目录名为准。

### 3.2 编译内核

| Wiki | 本工具 |
|---|---|
| `git clone .../kernel-rockchip --depth 1 -b nanopi6-v6.1.y kernel-rk3528` | `sdfuse-build kernel <OS>` 自动 clone 到 `RK_KERNEL_SRC` |
| `KERNEL_SRC=$PWD/kernel-rk3528 ./build-kernel.sh ubuntu-noble-core-arm64` | 同上，自动设置 `KERNEL_SRC` |

差异：源码目录名统一为 `kernel-rockchip`（与路线 B 共用，避免重复下载）；支持 `--kcfg`、`--no-third-party`、`--skip-distclean`。

### 3.3 编译内核头文件

| Wiki | 本工具 |
|---|---|
| `MK_HEADERS_DEB=1 BUILD_THIRD_PARTY_DRIVER=0 KERNEL_SRC=... ./build-kernel.sh <OS>` | `sdfuse-build headers <OS>` |

### 3.4 编译 uboot

| Wiki | 本工具 |
|---|---|
| `git clone .../uboot-rockchip --depth 1 -b nanopi5-v2017.09` | `sdfuse-build uboot <OS>` 自动 clone |
| `UBOOT_SRC=$PWD/uboot-rockchip ./build-uboot.sh <OS>` | 同上，自动设置 `UBOOT_SRC` |

### 3.5 生成新固件

| Wiki | 本工具 |
|---|---|
| `./mk-sd-image.sh ubuntu-noble-core-arm64`（固件在 `out/`） | `sdfuse-image sd <OS>`（额外复制一份到 `RK_OUTPUT_DIR`） |

Wiki 未列出但 sd-fuse README 提供的：`mk-emmc-image.sh <OS> autostart=yes`、`fusing.sh /dev/sdX <OS>`、`build-rootfs-img.sh`、`RAW_SIZE_MB`、`FS_TYPE=btrfs`、`SDFUSE_NONINTERACTIVE=y`、禁用 OverlayFS —— 本工具分别封装为 `sdfuse-image emmc`、`sdfuse-image fuse`、`--raw-size-mb`、`--no-overlayfs` 等（[04](04-sd-fuse打包.md)）。

---

## 4 本工具额外提供（Wiki 未涉及）

| 能力 | 说明 |
|---|---|
| `check-host --install` | 主机依赖自动检查与 apt 安装 |
| `install-toolchain` | 官方 prebuilts 安装方式脚本化，支持本地包 / URL |
| `config` / `status` | 配置与工作区可视化 |
| `--dry-run` / `RK_DRY_RUN` | 全流程预演，不落盘不写入 |
| 构建日志 `tee` | `logs/*.log` 保留每次编译输出 |
| 危险操作保护 | 预演默认、容量校验、分区备份、手工输入确认串 |
| `clean` | 只清本工具产物，不动源码 |
| 镜像加速 | `RK_GITHUB_MIRROR` / `RK_RAW_MIRROR` |
| 统一配置 | 所有 URL、分支、路径、OS 列表集中在 `config/sdk.conf` |
| 中文文档 | 环境、三条路线、烧录、命令、排错、本对照表 |
