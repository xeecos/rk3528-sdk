# 04 · 路线 C：sd-fuse 脚本化编译与打包

`sd-fuse_rk3528`（分支 `kernel-6.1.y`）是官方提供的一站式构建脚本集，用途：

- 把目录打包成分区镜像（例如 rootfs → `rootfs.img`）
- 把多个分区镜像合成可直接写 SD 卡的单一镜像
- 一键编译内核 / u-boot / 第三方驱动，并**自动更新** `<OS>/` 目录里的分区镜像（含解包重打 rootfs.img 中的内核模块）

本工具对它的封装命令为 `sdfuse-init` / `sdfuse-build` / `sdfuse-image`。

---

## 1. 官方脚本功能

| 脚本 | 作用 | 本工具入口 |
|---|---|---|
| `fusing.sh` | 把 `<OS>/` 下的分区镜像写入 SD 卡 | `sdfuse-image fuse` |
| `mk-sd-image.sh` | 生成 SD 卡启动镜像 | `sdfuse-image sd` |
| `mk-emmc-image.sh` | 生成 SD-to-eMMC 卡刷（eflasher）镜像 | `sdfuse-image emmc` |
| `build-rootfs-img.sh` | 目录 → `rootfs.img` | 直接调用官方脚本 |
| `build-kernel.sh` | 编译内核 / 内核头文件 | `sdfuse-build kernel / headers` |
| `build-uboot.sh` | 编译 u-boot | `sdfuse-build uboot` |
| `build-boot-img.sh` / `clean.sh` | 打包 boot 分区 / 清理 | 直接调用官方脚本 |

---

## 2. 支持的 OS 目录名

> **目录名在脚本内有严格定义，不可改名。**

```text
debian-trixie-core-arm64        ubuntu-noble-core-arm64
debian-bullseye-desktop-arm64   debian-bullseye-minimal-arm64
buildroot                       friendlywrt24
friendlywrt24-docker            friendlywrt25
friendlywrt25-docker            proxmox-arm64
eflasher                        alpine-linux-arm64
openmediavault-arm64
```

默认值 `RK_DEFAULT_OS=ubuntu-noble-core-arm64`。用 `./rk3528-sdk.sh sdfuse-image sd <OS>` 传其它值，或修改 `config/sdk.local.conf`。

---

## 3. 素材来源

| 素材 | 网盘位置 | 服务器 |
|---|---|---|
| 分区镜像 `*-images.tgz` | `03_分区镜像文件` | `https://downloads.friendlyelec.com/os-images/rk3528/images` |
| 文件系统包 `rootfs-*.tgz` | `06_文件系统` | `https://downloads.friendlyelec.com/rootfs/rk3528` |
| 内核源码 | `07_源代码` / GitHub `nanopi6-v6.1.y` | `RK_KERNEL_REPO` |
| U-Boot 源码 | `07_源代码` / GitHub `nanopi5-v2017.09` | `RK_UBOOT_REPO` |

**如果素材没提前准备，官方脚本会自己从服务器下载最新版**；本工具默认在 `sdfuse-init` 阶段就下载并解压，过程更可控。

---

## 4. 完整流程（WiKi 第 3 章 → 本工具）

WiKi 原始命令：

```bash
git clone https://github.com/friendlyarm/sd-fuse_rk3528.git -b kernel-6.1.y
cd sd-fuse_rk3528
tar xvzf /path/to/netdrive/03_分区镜像文件/ubuntu-noble-core-arm64-images.tgz

git clone https://github.com/friendlyarm/kernel-rockchip --depth 1 -b nanopi6-v6.1.y kernel-rk3528
KERNEL_SRC=$PWD/kernel-rk3528 ./build-kernel.sh ubuntu-noble-core-arm64

MK_HEADERS_DEB=1 BUILD_THIRD_PARTY_DRIVER=0 KERNEL_SRC=$PWD/kernel-rk3528 \
    ./build-kernel.sh ubuntu-noble-core-arm64

git clone https://github.com/friendlyarm/uboot-rockchip --depth 1 -b nanopi5-v2017.09
UBOOT_SRC=$PWD/uboot-rockchip ./build-uboot.sh ubuntu-noble-core-arm64

./mk-sd-image.sh ubuntu-noble-core-arm64     # 产物在 out/
```

本工具等价流程：

```bash
OS=ubuntu-noble-core-arm64

./rk3528-sdk.sh sdfuse-init "$OS" --with-eflasher
./rk3528-sdk.sh sdfuse-build kernel  "$OS"
./rk3528-sdk.sh sdfuse-build headers "$OS"      # 可选
./rk3528-sdk.sh sdfuse-build uboot   "$OS"      # 可选
./rk3528-sdk.sh sdfuse-image sd      "$OS"
./rk3528-sdk.sh sdfuse-image emmc    "$OS"
```

`sdfuse-init` 额外支持：

```bash
# 使用网盘本地文件，避免重复下载
./rk3528-sdk.sh sdfuse-init "$OS" --images /path/to/03_分区镜像文件/ubuntu-noble-core-arm64-images.tgz
# 使用自定义 URL
./rk3528-sdk.sh sdfuse-init "$OS" --images https://example.com/xxx-images.tgz
# 覆盖已有目录重新解压
./rk3528-sdk.sh sdfuse-init "$OS" --force
```

> `--with-eflasher` 会额外下载 `emmc-flasher-images.tgz` 并解压出 `eflasher/` 目录，这是 `sdfuse-image emmc` 的前置条件。

---

## 5. 环境变量

| 变量 | 作用 | 本工具中的设置方式 |
|---|---|---|
| `KERNEL_SRC` | 本地内核源码目录 | `sdfuse-build kernel/headers` 自动设为 `RK_KERNEL_SRC` |
| `KCFG` | 内核 defconfig（`arch/arm64/configs/` 下的文件名） | `sdfuse-build kernel --kcfg my_defconfig` |
| `MK_HEADERS_DEB` | `=1` 时只编译内核头文件 deb | `sdfuse-build headers` 自动设置 |
| `BUILD_THIRD_PARTY_DRIVER` | `=0` 跳过第三方驱动 | `--no-third-party`（headers 时自动设为 0） |
| `SKIP_DISTCLEAN` | `=1` 编译前不 distclean | `--skip-distclean` |
| `UBOOT_SRC` | 本地 u-boot 源码目录 | `sdfuse-build uboot` 自动设为 `RK_UBOOT_SRC` |
| `RAW_SIZE_MB` | 固件容量（MB），镜像装不下时调大 | `sdfuse-image sd/emmc --raw-size-mb 16000` |
| `FS_TYPE` | 根文件系统类型，如 `btrfs` | 直接 `FS_TYPE=btrfs ./rk3528-sdk.sh ...` |
| `SDFUSE_NONINTERACTIVE` | `=y` 跳过装包/下载前的询问 | 默认已由 `RK_SDFUSE_NONINTERACTIVE=y` 导出 |

自定义内核配置示例（官方 README）：

```bash
cd workspace/kernel-rockchip
touch .scmversion
make ARCH=arm64 nanopi5_linux_defconfig kvm.config
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- menuconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- savedefconfig
cp defconfig arch/arm64/configs/my_defconfig
cd -
./rk3528-sdk.sh sdfuse-build kernel ubuntu-noble-core-arm64 --kcfg my_defconfig
```

---

## 6. 进阶用法（直接调用官方脚本）

以下命令在 `workspace/sd-fuse_rk3528/` 目录内执行。

### 禁用 OverlayFS（量产 / Docker / Swap 场景）

```bash
cp prebuilt/parameter-plain.txt <OS>/parameter.txt
cp prebuilt/dtbo-plain.img      <OS>/dtbo.img
./mk-sd-image.sh <OS>
```

本工具封装为：`./rk3528-sdk.sh sdfuse-image sd <OS> --no-overlayfs`。

### 从自定义 rootfs 制作镜像

```bash
# 在开发板上备份根文件系统
sudo passwd root && su root
cd /
tar --warning=no-file-changed -cvpzf /rootfs.tar.gz \
    --exclude=/rootfs.tar.gz --exclude=/var/lib/docker/runtimes \
    --exclude=/etc/firstuse --exclude=/etc/friendlyelec-release \
    --exclude=/usr/local/first_boot_flag --one-file-system /

# 在主机上：解压务必用官方脚本（保权限），再用 sudo 打包
mkdir -p <OS>/rootfs
./tools/extract-rootfs-tar.sh rootfs.tar.gz <OS>/rootfs
sudo ./build-rootfs-img.sh <OS>/rootfs <OS>
./mk-sd-image.sh <OS>
```

从官方服务器取文件系统包：

```bash
wget https://downloads.friendlyelec.com/rootfs/rk3528/rootfs-debian-trixie-core-arm64.tgz
wget https://downloads.friendlyelec.com/rootfs/rk3528/rootfs-debian-trixie-core-arm64.tgz.sha256
sha256sum -c rootfs-debian-trixie-core-arm64.tgz.sha256
./tools/extract-rootfs-tar.sh rootfs-debian-trixie-core-arm64.tgz
```

### BTRFS 根文件系统

```bash
cat /proc/filesystems | grep btrfs        # 先确认内核支持，否则在 .config 加 CONFIG_BTRFS_FS=y
sudo -E FS_TYPE=btrfs ./build-rootfs-img.sh <OS>/rootfs <OS>
./mk-sd-image.sh <OS>
```

### 镜像太大装不下

```bash
RAW_SIZE_MB=16000 ./mk-sd-image.sh <OS>
RAW_SIZE_MB=16000 ./mk-emmc-image.sh <OS> autostart=yes
```

---

## 7. 产物命名

| 类型 | 文件名 |
|---|---|
| SD 启动镜像 | `out/rk3528-sd-<OS>-6.1-arm64-YYYYMMDD.img` |
| SD-to-eMMC 卡刷镜像 | `out/rk3528-eflasher-<OS>-6.1-arm64-YYYYMMDD.img` |

`sdfuse-image sd/emmc` 会把 `workspace/sd-fuse_rk3528/out/` 下的新镜像复制一份到 `RK_OUTPUT_DIR`（默认 `./out/`），方便统一取用。

`autostart=yes` 表示用该卡刷固件开机后**自动进入烧写流程**，无需人工确认。

---

## 8. 常见问题

- **制作 rootfs 后无法启动**：多半是文件权限被破坏，必须用 `tools/extract-rootfs-tar.sh` 解压、用 `tar -cpzf` 打包（保留权限）。
- **打包过程中进程退出**：内存不足，加内存或 swap。
- **脚本一直询问**：确认 `SDFUSE_NONINTERACTIVE=y` 已导出（本工具默认设置）。
- **提示缺少分区镜像**：`sdfuse-init <OS>` 重新准备；eflasher 需要 `--with-eflasher`。
