# logs/

构建日志目录（**目录内所有 `*.log` 均被 `.gitignore` 忽略，仅本 README 入库**）。

Git 不追踪空目录，本文件用于让目录结构随仓库一起提交。目录由脚本自动创建。

耗时构建命令通过 `run_in_logged`（内部 `tee -a`）同步写入日志：

| 日志前缀 | 来源 |
|---|---|
| `fw-build-*.log` | `fw-build all/docker/uboot/kernel/...` |
| `fw-rebuild-*.log`、`fw-single-*.log` | `fw-build rebuild/single` |
| `kernel-build-*.log`、`kernel-modules-*.log` | `kernel-build` |
| `uboot-build-*.log` | `uboot-build` |
| `sdfuse-{kernel,headers,uboot,image}-*.log` | `sdfuse-build` / `sdfuse-image` |

排错时先看最近一份日志的尾部：

```bash
ls -lt logs/ | head
tail -100 logs/<日志文件>
```

`./rk3528-sdk.sh clean logs` 可清理；`fw-build --no-log` 可关闭单次构建的日志写入。
