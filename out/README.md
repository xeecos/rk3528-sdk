# out/

构建产物目录（**目录内所有内容均被 `.gitignore` 忽略，仅本 README 入库**）。

Git 不追踪空目录，本文件用于让目录结构随仓库一起提交。目录由脚本自动创建。

| 子目录 / 文件 | 来源命令 | 内容 |
|---|---|---|
| `manual-kernel/` | `kernel-build` | `kernel.img`、`resource.img`、`kernel-modules-<ver>.tar.gz` |
| `manual-uboot/` | `uboot-build` | `uboot.img`、`trust.img`、`MiniLoaderAll.bin` |
| `partition-backup-<时间戳>/` | `install-board` | dd 写入前的原分区备份 |
| `rk3528-sd-*.img` | `sdfuse-image sd` | SD 卡启动固件（从 sd-fuse 的 `out/` 复制一份） |
| `rk3528-eflasher-*.img` | `sdfuse-image emmc` | SD-to-eMMC 卡刷固件 |

FriendlyWrt 全量工程的镜像另外位于 `workspace/friendlywrt25-rk3528/out/`，sd-fuse 原始产物位于 `workspace/sd-fuse_rk3528/out/`。

> 固件体积通常为数 GB，不要提交到 Git。用 `./rk3528-sdk.sh clean images` 可安全清理本目录下的产物（不会动 `workspace/` 源码）。
