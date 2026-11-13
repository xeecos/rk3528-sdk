# 10 · ZTE W132D 主线 Linux（路线 D）

上游：[zte-cloud-computer/w132d-linux-mainline](https://github.com/zte-cloud-computer/w132d-linux-mainline)

## 1. 这是什么

**ZTE Cloud Computer W132D** 是一台流入二手市场的运营商云终端：**RK3528 + UWE5621DS** 无线模块，
常见配置 2 GB DDR4 + 32 GB eMMC。上游项目为它提供 **Debian trixie minimal** 系统，基于
Linux 稳定内核、主线 U-Boot 与 Armbian 构建框架，附带板级驱动、USB 刷写包和签名 APT 更新源。

上游 `config/sources.json` 当前锁定的快照（会随 Release 更新）：

| 组件 | 锁定版本 |
|---|---|
| Linux | `v7.2.10`（kernel.org stable） |
| Armbian build | `v26.5.1` |
| U-Boot | `v2026.10` |
| 发行版 | Debian `trixie` minimal，branch `edge` |

> 本仓库**不复制上游源码**，只在 `w132d init` 时按需 clone 到 `workspace/w132d-linux-mainline`，
> 所有构建动作都转发给上游的 `tools/w132d`。这样上游更新时无需改动本仓库。

---

## 2. 与 FriendlyELEC BSP 的边界（务必先读）

W132D 与路线 A/B/C **同 SoC，但属于两套完全独立的固件体系**：

| 项目 | 路线 A/B/C（FriendlyELEC BSP） | 路线 D（W132D 主线） |
|---|---|---|
| 内核 | `kernel-rockchip` `nanopi6-v6.1.y` 厂商 BSP | Linux stable `v7.2.10` + 板级补丁 |
| U-Boot | `uboot-rockchip` `v2017.09` `/ nanopi_r3` | 主线 U-Boot `v2026.10` |
| 构建框架 | `repo` + `build.sh` / `sd-fuse_rk3528` | Armbian build + `tools/w132d` |
| 分区布局 | Rockchip 参数分区（uboot/trust/resource/kernel/boot…） | Armbian GPT：FAT boot 512 MiB + ext4 rootfs，idbloader@64 sector、uboot@16384 |
| 引导 | Rockchip resource / kernel 分区 | extlinux + 主线 U-Boot |
| 工具链 | `/opt/FriendlyARM/toolchain/11.3-aarch64` | Armbian 容器内工具链（amd64 走 binfmt/QEMU） |
| 产物 | `kernel.img` / `resource.img` / SD 镜像 | `w132d.img`、`.deb` 包、`manifest.json` |
| 刷写 | `dd` 分区更新 / `upgrade_tool` / `fusing.sh` | USB `rkdeveloptool` 整盘刷写（`flash.sh`） |

**结论：两套固件不可混刷、产物不可互换、分区镜像不可复用。** 本工具把 W132D 的源码、
下载、产物、刷写包全部放在独立目录，不会污染 `workspace/kernel-rockchip`、`sd-fuse_rk3528`
或 `out/manual-*`。`install-board`、`flash-loader`、`sdfuse-image` **都不适用于 W132D**。

---

## 3. 快速开始

### 3.1 从源码构建（需要 Docker）

```bash
./rk3528-sdk.sh w132d init                  # clone 上游 + 环境体检
./rk3528-sdk.sh w132d fetch --download      # 锁定并下载上游来源 → out/manifest.json
./rk3528-sdk.sh w132d build kernel          # 只构建内核/DTB/headers 软件包
./rk3528-sdk.sh w132d build image           # 完整 Armbian 镜像 w132d.img
./rk3528-sdk.sh w132d verify static         # 与 CI 一致的静态检查
./rk3528-sdk.sh w132d status                # 查看版本与产物
```

产物位于 `workspace/w132d-linux-mainline/out/<version>/`，
其中 `<version>` 可从 `out/manifest.json` 读取。

### 3.2 直接刷官方 Release（不需要 Docker）

```bash
./rk3528-sdk.sh w132d flash                 # 下载 zip + SHA256SUMS、校验、解压、flash.sh --dry-run
./rk3528-sdk.sh w132d flash --execute       # 确认后真正刷写（高危）
./rk3528-sdk.sh w132d flash --tag <TAG>     # 固定版本，避免 latest 漂移
```

默认只做校验与只读自检，**不会访问 USB**。

---

## 4. 命令参考

| 命令 | 作用 |
|---|---|
| `w132d init [--ref REF] [--check-only]` | clone 上游；`--ref` 可切到指定 tag/commit；`--check-only` 只体检 |
| `w132d fetch [--latest] [--channel stable\|experimental] [--detect] [--no-download]` | 生成/下载来源锁；默认 `--download`、channel `experimental` |
| `w132d build [kernel\|image\|uboot\|bsp\|flash-tools\|fnos]` | 默认 `kernel`；`image` 出完整镜像 |
| `w132d build ... --framework PATH` | 指定 Armbian 框架目录 |
| `w132d build flash-tools --output DIR` | 本地编译 rkdeveloptool（**不依赖 Docker**） |
| `w132d build fnos --base-image FILE --base-sha256 HEX` | 实验性 fnOS 镜像 |
| `w132d verify <static\|tests\|patches\|debs\|image\|candidate> [--jobs N] [--directory D] [--image F] [--full] [--docker]` | 与 CI 一致的检查；`--docker` 用官方 `w132d-check` 容器 |
| `w132d flash [--tag TAG] [--execute] [--verify-only]` | Release 刷写包下载、校验、自检、刷写 |
| `w132d status` | 上游提交、manifest 版本、产物、刷写包、环境依赖 |

`--docker` 首次使用需先构建官方检查镜像：

```bash
cd workspace/w132d-linux-mainline
docker build -t w132d-check -f tools/docker/Dockerfile .
```

所有耗时动作通过 `run_in_logged` 写日志到 `logs/w132d-*.log`；
`RK_DRY_RUN=1` 可完整预演而不落盘、不刷写。

---

## 5. 环境依赖

主机支持矩阵**不变**（原生 Ubuntu 20.04/22.04/24.04 x86_64 或 Win11 WSL2）。
W132D 路线额外要求：

| 依赖 | 用途 | 说明 |
|---|---|---|
| Docker | Armbian 构建框架 | `build kernel/image/uboot/bsp` 必需；`build flash-tools` 与 `w132d flash` 不需要 |
| Python **3.12+** | `tools/w132d` / Armbian | 刷写脚本 `flash.py` 只需 3.9+ |
| `dtc`、`gdisk`/`sgdisk`、`fdisk` | DTB 与镜像分区 | 由 Armbian 补齐其余依赖 |
| loop 设备 | 完整镜像构建 | WSL2 内核 `CONFIG_BLK_DEV_LOOP=y`，但需确认 `/dev/loop-control` 存在 |
| 磁盘 | ≥ **35 GiB** | 上游 `docs/build.md` 要求 |
| `curl`、`unzip` | 下载/解压刷写包 | `check-host --install` 已包含 |
| `git` | clone 上游 | 已包含 |

> **关于 Docker 与「Docker 非目标」的口径**：这里 Docker 是 W132D 上游 Armbian 框架的**构建依赖**
> （一个跑在受支持 Linux 主机里的容器），不是把 Docker 当成新的受支持平台。主机支持矩阵不变。
> WSL2 下可用 Docker Desktop 的 WSL2 backend 或 WSL2 内原生 `dockerd`。

---

## 6. 刷写

`w132d flash` 从 GitHub Release 下载 `w132d-flash.zip` 与 `SHA256SUMS`，核对摘要后解压到
`downloads/w132d-flash/<tag|latest>/`，设置执行权限，再调用上游 `flash.sh`。

刷写包内容：`flash-manifest.json`、`image-head.bin`、`image-system.bin`、`loader.bin`、
`flash.sh` / `flash.py` / `flash.ps1`、`tools/<platform>/rkdeveloptool`。

**进入 USB 下载模式**（上游 `docs/install.md`）：

1. 设备断电，按住 Reset 针孔按键（HDMI / USB 3.0 口旁）。
2. 保持按住，接通电源并用 USB 数据线**直连**电脑，约 5 秒后松开。
3. 电脑只连接一台 Rockchip 设备，全程保持稳定供电。

```bash
./rk3528-sdk.sh w132d flash                # 自检，输出 FLASH_DRY_RUN_OK 即包完整
sudo ./flash.sh                            # 由 w132d flash --execute 代执行
sudo ./flash.sh --verify-only               # 只读回读校验（w132d flash --verify-only）
```

脚本会识别 RK3528、处理 Loader/MaskROM、加载配套 loader、检查容量后按清单写入并**完整回读**，
保留 vendor storage / RKSS 区间；出现 `FLASH_OK` 后自动重启。

⚠️ **刷写会替换系统和分区表，不可撤销，请先备份原厂恢复材料。**
本工具在 `--execute` 前要求手工输入 `FLASH` 确认串，`--verify-only` 要求输入 `VERIFY`。

### Windows / WSL2 的现实限制

- 上游明确：**Windows 刷写路径尚未确认实机兼容性**，刷写包只附 Linux amd64 / Linux arm64 / macOS arm64 的 rkdeveloptool。
- WSL2 默认内核**未启用 `CONFIG_USB_STORAGE`**，`wsl --mount` 也不支持 USB 读卡器；`usbipd-win` 直通未获上游验证。
- 因此**建议在原生 Ubuntu x86_64 物理机上刷写**。`w132d flash` 在 WSL2 下会主动给出警告。

首次启动：`ssh root@<设备IP>`，默认密码 `1234`，首次登录强制改密并创建普通用户；
根分区自动扩容；有线 MAC 由 SoC OTP 派生，可能与机身标签不同。

---

## 7. 硬件支持与已知限制

来自上游 `docs/hardware.md`（**上游标注硬件实机验证仍在进行中**）：

| 功能 | 范围 |
|---|---|
| 存储 | eMMC，含 HS400 Enhanced Strobe |
| 网络 | 10/100 Mbps 有线、UWE5621DS Wi-Fi（Marlin3E 固件协议） |
| 蓝牙 / 红外 | 原生 HCI + BlueZ + BLE 遥控；NEC 0x22 键表 |
| 音频 | RK3528 DAC 3.5 mm 输出、ES7202 麦克风输入 |
| HDMI | **1080p60 确认支持**；1440p / 4K30 / 4K60 驱动已配置但实机兼容性待确认 |
| 图形视频 | Lima GPU、RKVDEC H.264/HEVC |
| 其他 | 温控、DVFS、watchdog、pstore、面板灯、软件待机 |

已知限制：无 HDCP / CVBS / 系统 suspend；HDMI 仅 RGB 8-bit，未打通 YCbCr 4:2:0、10-bit、HDR；
BLE 遥控桥接只覆盖特定协议；公开镜像不含私有语音解码器；fnOS 实验镜像不适用 Armbian 内核 APT 升级流程。
**仅适用 RK3528 + UWE5621DS 的 W132D**，外观相似的其他云终端或无线模块变体不在适配范围。

---

## 8. 故障排查

| 现象 | 处理 |
|---|---|
| `build image` 提示需要 Docker | 安装并启动 docker；`build flash-tools` 与 `w132d flash` 不需要 |
| Python 版本过低 | 构建需 3.12+，刷写需 3.9+；`w132d init` / `w132d status` 会体检并警告 |
| 提示 `out/manifest.json` 缺失 | 先跑 `w132d fetch --download` |
| 完整镜像构建失败 / loop 报错 | WSL2 下检查 `ls -l /dev/loop-control`，必要时 `wsl --shutdown` 后重进；或换原生 Ubuntu |
| 磁盘不足 | 上游要求 ≥ 35 GiB；把 `RK_WORKSPACE` 指向大盘（WSL2 用 ext4，不要 `/mnt/*`） |
| `SHA256SUMS` 中找不到 zip / 校验失败 | 重新下载；或用 `--tag <固定版本>` 锁定，避免 latest 资产变动 |
| 未出现 `FLASH_DRY_RUN_OK` | 刷写包不完整或结构变化，检查 `downloads/w132d-flash/<tag>/` |
| USB 设备识别不到 | 确认 Reset 按键时序、数据线、只连一台；WSL2 下优先换 Ubuntu 物理机 |
| 刷写中断 | 保持供电，重新进入下载模式，用**同一个完整包**重试；参见上游 `docs/recovery.md` |

---

## 9. 许可与来源

上游工具与脚本为 MIT；内核、驱动、U-Boot、rkdeveloptool、libusb 与外部二进制各自遵循其许可，
上游 MIT 不覆盖这些组件。来源清单见上游 `config/sources.json`、
`userpatches/extensions/w132d/drivers/SOURCES.json`、`vendor/rkdeveloptool/SOURCE.json`。
本仓库只做编排，不重新分发上游代码。
