# workspace/

源码工作区（**目录内所有内容均被 `.gitignore` 忽略，仅本 README 入库**）。

Git 不追踪空目录，本文件用于让目录结构随仓库一起提交；脚本首次运行时会自动创建所需子目录。

脚本会在本目录下生成：

| 子目录 | 来源 | 说明 |
|---|---|---|
| `friendlywrt25-rk3528/` | `fw-init` | FriendlyWrt 25.12 repo 多仓库工程 |
| `sd-fuse_rk3528/` | `sdfuse-init` | sd-fuse 脚本 + 各 OS 分区镜像目录 |
| `kernel-rockchip/` | `kernel-build` / `sdfuse-build` | 内核源码 `nanopi6-v6.1.y` |
| `uboot-rockchip/` | `uboot-build` / `sdfuse-build` | U-Boot 源码 `nanopi5-v2017.09` |
| `rkbin/` | `uboot-build` | 必须与 `uboot-rockchip/` 同级 |
| `prebuilts/` | `install-toolchain` | 工具链压缩包缓存 |
| `w132d-linux-mainline/` | `w132d init` | 路线 D 上游：主线 Linux + Armbian，**与上面 FriendlyELEC BSP 完全独立** |

> 源码体积可达数十 GB。空间不足时把 `RK_WORKSPACE` 配置到大容量磁盘（见 `config/sdk.local.conf.example`），不必放在本仓库内。
