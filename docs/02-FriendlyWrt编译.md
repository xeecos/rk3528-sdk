# 02 · 路线 A：FriendlyWrt 25.12 全量编译

对应 WiKi 第 1 章「编译 Openwrt/Friendlywrt」。这是一条**从零构建整套系统**的路线：`u-boot` → `kernel` → `friendlywrt rootfs` → SD 镜像 → eMMC 卡刷固件。

---

## 1. 下载源码（`fw-init`）

WiKi 原始命令：

```bash
mkdir friendlywrt25-rk3528
cd friendlywrt25-rk3528
git clone https://github.com/friendlyarm/repo --depth 1 tools
tools/repo init -u https://github.com/friendlyarm/friendlywrt_manifests -b master-v25.12 \
        -m rk3528.xml --repo-url=https://github.com/friendlyarm/repo --no-clone-bundle
tools/repo sync -c --no-clone-bundle
```

本工具等价命令：

```bash
./rk3528-sdk.sh fw-init
# 自定义 manifest：./rk3528-sdk.sh fw-init --branch master-v25.12 --manifest rk3528.xml --jobs 4
# 切换 manifest 不删源码：./rk3528-sdk.sh fw-init --force
```

`rk3528.xml`（`master-v25.12`）包含的项目：

| path | 仓库 | 分支 |
|---|---|---|
| `kernel` | kernel-rockchip | `nanopi6-v6.1.y` |
| `u-boot` | uboot-rockchip | `nanopi5-v2017.09` |
| `rkbin` | rkbin | `nanopi5` |
| `scripts/sd-fuse`（link `out`） | sd-fuse_rk3528 | `kernel-6.1.y` |
| `device/common` | friendlywrt_device_common | `master` |
| `device/friendlyelec` | friendlywrt_device_rk3528 | `master-v25.12` |
| `configs` | friendlywrt_configs | `master-v25.12` |
| `scripts`（link `build.sh`） | friendlywrt_scripts | `master` |
| `friendlywrt` | friendlywrt | `master-v25.12` |
| `toolchain` | prebuilts | `master` |

> `repo sync` 中断后**直接重跑 `fw-init` 即可续传**，脚本检测到 `.repo` 已存在会跳过 `repo init`。
> 工程自带 `toolchain/`，所以这条路线**不依赖** `/opt/FriendlyARM/toolchain`。

---

## 2. 首次全量编译

```bash
./rk3528-sdk.sh fw-build all        # ./build.sh rk3528.mk（不带 docker）
./rk3528-sdk.sh fw-build docker     # ./build.sh rk3528-docker.mk（带 docker）
```

`build.sh <板级 .mk>` 内部依次执行：

```
选择配置 → 生成 .current_config.mk 软链接 → install_toolchain
         → build_uboot → build_kernel → build_friendlywrt → build_sdimg
```

即**自动包含 SD 镜像**，但**不包含 eMMC 卡刷固件**，需要额外执行：

```bash
./rk3528-sdk.sh fw-build emmc-img
```

若项目有改动、只需重新打包：

```bash
./rk3528-sdk.sh fw-build sd-img
```

产物位于 `workspace/friendlywrt25-rk3528/out/`。

---

## 3. `build.sh` 目标对照表

`friendlywrt_scripts/build.sh` 只接受 **1 个参数**。参数若在 `device/friendlyelec/` 下能找到同名 `.mk`，会被当作「板级配置」并触发全量编译；否则按固定目标分派，且要求已经存在 `.current_config.mk`。

| `fw-build` 目标 | 实际执行 | 说明 |
|---|---|---|
| `all` | `./build.sh rk3528.mk` | 选板 + 全量编译 + SD 镜像 |
| `docker` | `./build.sh rk3528-docker.mk` | 同上，docker 版 |
| `uboot` | `./build.sh uboot` | 只编译 u-boot |
| `kernel` | `./build.sh kernel` | 只编译内核 |
| `friendlywrt` | `./build.sh friendlywrt` | 只编译 rootfs（feeds 更新 + 补丁 + 打包） |
| `sd-img` | `./build.sh sd-img` | 重新打 SD 卡镜像（会检查 u-boot/kernel/模块是否已构建） |
| `emmc-img` | `./build.sh emmc-img` | 生成 eflasher 卡刷固件；缺 `eflasher/rootfs.img` 时自动 `tools/get_rom.sh eflasher` |
| `menuconfig` | `(cd friendlywrt && make menuconfig)` | 交互改配置 |
| `rebuild` | 见下节 | 二次编译四连 |
| `single` | `(cd friendlywrt && make -j1 V=s)` | 单线程排错 |
| `clean` | `./build.sh clean` | 删 out/ 下旧镜像 |
| `cleanall` | `./build.sh cleanall` | u-boot/kernel `distclean` + friendlywrt `clean` + sd-fuse `clean.sh`（内部会 sudo 重跑） |

`build.sh` 另有未在 WiKi 列出的 `all`、`u-boot` 别名，本工具统一用 `uboot`。

> 若直接执行 `./build.sh sd-img` 而没先选过板，会报 `no .current_config.mk, please select a board first.`。本工具会提前给出更清晰的提示。

---

## 4. 二次编译（改动配置之后）

WiKi 原始流程：

```bash
cd friendlywrt
make menuconfig          # 改动 FriendlyWrt 的配置
rm -rf ./tmp
make -j${nproc}
cd ../
./build.sh sd-img
./build.sh emmc-img
```

本工具拆成两步：

```bash
./rk3528-sdk.sh fw-build menuconfig     # 改配置（交互式）
./rk3528-sdk.sh fw-build rebuild        # 清 tmp → make -jN → sd-img → emmc-img
```

> WiKi 里的 `make -j${nproc}` 是笔误（`${nproc}` 不是有效命令），脚本使用真实的 `nproc` 值，可用 `RK_JOBS` 覆盖。
> `rebuild` 在删除 `friendlywrt/tmp` 前会**明确列出路径并请求确认**；若只想快速增量编译，在提示时选 `N` 即可跳过清理。预演模式（`--dry-run`）只打印该删除命令，不会真的删除。

---

## 5. 编译报错时的单线程排错

```bash
./rk3528-sdk.sh fw-build single           # (cd friendlywrt && make -j1 V=s)
./rk3528-sdk.sh fw-build single --docker  # docker 版先 rm -rf tmp/go-build 清 go 缓存
```

单线程 + `V=s` 能把真正出错的目标打印出来，多线程日志里常被淹没。docker 版常见 go 编译缓存损坏，清 `tmp/go-build` 后重试。

---

## 6. 产物与后续

```text
workspace/friendlywrt25-rk3528/out/
├── rk3528-sd-friendlywrt25-6.1-arm64-YYYYMMDD.img(.gz)      SD 启动镜像
└── rk3528-eflasher-friendlywrt25-6.1-arm64-YYYYMMDD.img(.gz) eMMC 卡刷固件
```

烧写与更新见 [05-烧录与更新.md](05-烧录与更新.md)。

---

## 7. 常见注意点

- **不要用 root 编译**：OpenWrt 明确拒绝；`fw-build` 会主动检查并退出。
- **磁盘**：`fw-init` 前会检查 `RK_MIN_FREE_GB`（默认 50），空间不足直接中止，避免编译到一半失败。
- **日志**：`fw-build all|docker|rebuild|single` 通过 `tee` 写到 `logs/`，失败时先查日志尾部。
- **选板是一次性动作**：`.current_config.mk` 是软链接，`fw-build all` 会重新指向 `rk3528.mk`，`fw-build docker` 会指向 `rk3528-docker.mk`，切换后增量目标会跟着变。
- **清空镜像**：`fw-build clean` 只删 out 下的镜像文件；`cleanall` 会 distclean，代价大，勿在赶时间时用。
