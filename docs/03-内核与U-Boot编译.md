# 03 · 路线 B：手工编译内核与 U-Boot

对应 WiKi 第 2 章「其他Linux系统编译」。适用于以下系统（均为 linux v6.1.y + u-boot v2017.09 + 11.3-aarch64）：

```text
friendlywrt25   friendlywrt25-docker   ubuntu-noble-core-arm64
openmediavault-arm64   debian-trixie-core-arm64
```

这条路线**不依赖 sd-fuse**，直接产出可写入 GPT 分区的 `kernel.img` / `resource.img` / `uboot.img`，适合改内核配置、改 DTB、验证驱动模块。若想让编译结果自动回填到系统镜像目录，请改用[路线 C](04-sd-fuse打包.md)。

---

## 1. 编译内核 linux-v6.1.y

### 本工具命令

```bash
./rk3528-sdk.sh kernel-build                    # Linux 系统配置
./rk3528-sdk.sh kernel-build --friendlywrt     # 追加 friendlywrt.config
./rk3528-sdk.sh kernel-build --menuconfig      # 交互式改配置
./rk3528-sdk.sh kernel-build --pack-only       # 源码已编译好，只重新打包 img
```

### 对应的 WiKi 原始流程

```bash
git clone https://github.com/friendlyarm/kernel-rockchip \
    --single-branch --depth 1 -b nanopi6-v6.1.y kernel-rockchip
cd kernel-rockchip
export PATH=/opt/FriendlyARM/toolchain/11.3-aarch64/bin/:$PATH
touch .scmversion

# option1：Linux 系统配置
make CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm64 nanopi5_linux_defconfig
# option2：FriendlyWrt 系统配置
# make CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm64 nanopi5_linux_defconfig friendlywrt.config
# make CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm64 menuconfig

make CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm64 -j$(nproc)

mkdir -p out-modules && rm -rf out-modules/*
make CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm64 INSTALL_MOD_PATH="$PWD/out-modules" modules -j$(nproc)
make CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm64 INSTALL_MOD_PATH="$PWD/out-modules" modules_install
KERNEL_VER=$(make CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm64 kernelrelease)
[ ! -f "$PWD/out-modules/lib/modules/${KERNEL_VER}/modules.dep" ] && \
    depmod -b $PWD/out-modules -E Module.symvers -F System.map -w ${KERNEL_VER}
(cd $PWD/out-modules && find . -name \*.ko | xargs aarch64-linux-strip --strip-unneeded)
```

脚本的实现差异（更稳健，行为等价）：

| 环节 | 脚本做法 |
|---|---|
| 工具链 | `setup_toolchain_path` 自动导出 PATH / `CROSS_COMPILE` / `ARCH` |
| defconfig | `--friendlywrt` 追加 `friendlywrt.config`；`--defconfig NAME` 可自定义 |
| 线程 | `RK_JOBS` 或 `nproc`，可用 `--jobs N` 覆盖 |
| 清理模块目录 | 只清 `out-modules/` 内部，不动源码其它内容 |
| `depmod` | 自动查找 `depmod` 或 `/sbin/depmod`，仅当 `modules.dep` 不存在时执行 |
| `strip` | `find -print0 \| xargs -0 -r`，无 .ko 时不会报错 |
| 模块交付 | 额外打包 `kernel-modules-<版本>.tar.gz` 到 `out/manual-kernel/` |
| 日志 | 内核与模块编译分别 `tee` 到 `logs/` |

### 配置说明

| 目标系统 | defconfig | 说明 |
|---|---|---|
| Ubuntu Noble / Debian Trixie / OMV | `nanopi5_linux_defconfig` | 默认 |
| FriendlyWrt 25 / 25-docker | `nanopi5_linux_defconfig` + `friendlywrt.config` | 加 `--friendlywrt` |

自定义配置保存方法（sd-fuse 的 `KCFG` 也能用这类文件）：

```bash
cd workspace/kernel-rockchip
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- menuconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- savedefconfig
cp defconfig arch/arm64/configs/my_defconfig
# 之后：./rk3528-sdk.sh kernel-build --defconfig my_defconfig
```

---

## 2. 打包 kernel.img 与 resource.img

WiKi 原始命令：

```bash
wget https://raw.githubusercontent.com/friendlyarm/sd-fuse_rk3528/kernel-6.1.y/tools/mkkrnlimg && chmod 755 mkkrnlimg
wget https://raw.githubusercontent.com/friendlyarm/sd-fuse_rk3528/kernel-6.1.y/tools/resource_tool && chmod 755 resource_tool
wget https://raw.githubusercontent.com/friendlyarm/sd-fuse_rk3528/kernel-6.1.y/prebuilt/boot/logo.bmp
wget https://raw.githubusercontent.com/friendlyarm/sd-fuse_rk3528/kernel-6.1.y/prebuilt/boot/logo_kernel.bmp
./mkkrnlimg arch/arm64/boot/Image kernel.img
./resource_tool --dtbname arch/arm64/boot/dts/rockchip/rk3528-nanopi*-rev*.dtb logo.bmp logo_kernel.bmp
```

脚本把这些文件缓存到 `downloads/tools/`，在 `out/manual-kernel/` 中执行打包，产物集中不污染源码树：

> **架构适配**：官方仓库同时提供 `tools/`（x86_64 ELF）与 `tools/aarch64/`（arm64 ELF）两套
> `mkkrnlimg` / `resource_tool`。脚本按 `uname -m` 自动选择，也可用
> `RK_SDFUSE_TOOL_ARCH=x86_64|aarch64` 强制指定。在非 x86_64 主机上必须用 aarch64 版，
> 否则会报 `Exec format error`。两个受支持平台（Ubuntu x86_64 / WSL2）都走 `tools/`，无需设置；
> 这段自动检测只是为非目标平台/CI 保留的通用实现。

- `mkkrnlimg`：`arch/arm64/boot/Image` → `kernel.img`
- `resource_tool`：把匹配 `rk3528-nanopi*-rev*.dtb` 的全部 DTB + 两张开机 logo → `resource.img`

> 若 `raw.githubusercontent.com` 访问不通，设置 `RK_RAW_MIRROR`（如 `https://ghproxy.net/`），或把 4 个文件手工放到 `downloads/tools/` 后重跑。
> 脚本会检查 `mkkrnlimg` 是否为 ELF 可执行文件（防止下载到 HTML 错误页）。

### 产物

| 文件 | 位置 | 用途 |
|---|---|---|
| `kernel.img` | `out/manual-kernel/` | 写入 GPT 分区 6 (`kernel`) |
| `resource.img` | `out/manual-kernel/` | 写入 GPT 分区 5 (`resource`) |
| `kernel-modules-<ver>.tar.gz` | `out/manual-kernel/` | 解压后替换开发板 `/lib/modules` |
| `out-modules/` | `workspace/kernel-rockchip/` | 未打包的模块目录 |

---

## 3. 编译 u-boot v2017.09

WiKi 原始命令：

```bash
git clone https://github.com/friendlyarm/rkbin --single-branch --depth 1 -b friendlyelec
git clone https://github.com/friendlyarm/uboot-rockchip --single-branch --depth 1 -b nanopi5-v2017.09
export PATH=/opt/FriendlyARM/toolchain/11.3-aarch64/bin/:$PATH
cd uboot-rockchip/
./make.sh nanopi_r3
```

本工具：

```bash
./rk3528-sdk.sh uboot-build
# 已有源码：./rk3528-sdk.sh uboot-build --no-clone
# 改板级目标：./rk3528-sdk.sh uboot-build --board nanopi_r3
```

> **关键约束**：`rkbin` 必须与 `uboot-rockchip` **同级**（`make.sh` 按 `../rkbin` 找 BL31/BL32 等固件）。脚本默认两者都在 `workspace/` 下，会检查并在不同级时告警。

编译后脚本自动收集到 `out/manual-uboot/`：

| 官方产物 | 收集后 | 用途 |
|---|---|---|
| `uboot.img` | `uboot.img` | 写入 GPT 分区 1 (`uboot`) |
| `trust.img` | `trust.img` | 写入 GPT 分区 2 (`trust`) |
| `rk356x_spl_loader_vX.YY.ZZZ.bin` | `MiniLoaderAll.bin` | 线刷 / sd-fuse 打包固件时使用 |

---

## 4. 应用编译结果

三条路可选，详见 [05-烧录与更新.md](05-烧录与更新.md)：

```bash
# ① 在开发板上 dd 更新分区（默认预演，确认后 --execute）
sudo ./rk3528-sdk.sh install-board --device /dev/mmcblk2 \
     --img-dir /abs/path/out/manual-kernel --execute

# ② 主机线刷（开发板先 sudo reboot loader）
sudo ./rk3528-sdk.sh flash-loader --img-dir /abs/path/out/manual-kernel --execute

# ③ 放进 sd-fuse 的 <OS>/ 目录，重新打包完整固件
cp out/manual-kernel/{kernel.img,resource.img} workspace/sd-fuse_rk3528/<OS>/
./rk3528-sdk.sh sdfuse-image sd <OS>
```

**务必同时更新内核模块**：只刷 `kernel.img` 而 `/lib/modules` 仍是旧版本，会出现驱动加载失败、网络/USB 异常。把 `kernel-modules-<ver>.tar.gz` 传到板上，解压到 `/lib/modules` 后重启。
