# downloads/

下载缓存目录（**目录内所有内容均被 `.gitignore` 忽略，仅本 README 入库**）。

Git 不追踪空目录，本文件用于让目录结构随仓库一起提交。脚本会自动创建本目录及 `tools/` 子目录。

缓存内容：

| 文件 / 目录 | 用途 |
|---|---|
| `<OS>-images.tgz` | sd-fuse 分区镜像包，来自 `downloads.friendlyelec.com` 或网盘 |
| `emmc-flasher-images.tgz` | eflasher 系统镜像包（`--with-eflasher`） |
| `toolchain-11.3-aarch64.tar.xz` | 通过 `RK_TOOLCHAIN_URL` 下载时的工具链包 |
| `tools/mkkrnlimg` | 打包 `kernel.img` |
| `tools/resource_tool` | 打包 `resource.img` |
| `tools/logo.bmp`、`tools/logo_kernel.bmp` | 开机 logo |
| `tools/upgrade_tool` | 可选放置的 Rockchip 线刷工具 |

`download()` 对已存在且非空的文件会跳过下载，因此中断后重跑不会重复拉大文件。
可通过 `RK_DOWNLOAD_DIR` 改到大容量磁盘；用 `--images FILE` / `--package FILE` 可直接使用网盘本地文件。
