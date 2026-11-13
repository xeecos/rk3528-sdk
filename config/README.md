# config/

构建配置目录。所有路径、上游仓库地址、分支、目标系统名称都集中在这里，脚本本身不写死这些值。

| 文件 | 说明 | 是否入库 |
|---|---|---|
| `sdk.conf` | 默认配置，含完整变量注释 | 是 |
| `sdk.local.conf.example` | 通用本机配置模板 | 是 |
| `sdk.wsl.conf.example` | WSL2 专用模板：把工作区指向 WSL 原生 ext4（`/home/...`） | 是 |
| `sdk.local.conf` | 本机私有配置（可含自定义路径/令牌） | **否**，已 gitignore |

Windows / WSL2 用户请复制 WSL 模板，见 [docs/09-WSL2构建指南.md](../docs/09-WSL2构建指南.md)：

```bash
cp config/sdk.wsl.conf.example config/sdk.local.conf
```

## 加载优先级

从低到高：`sdk.conf` → `sdk.local.conf` → `$RK_CONF` 指定的文件 → 同名环境变量。

```bash
cp sdk.local.conf.example sdk.local.conf
vi sdk.local.conf
./rk3528-sdk.sh config              # 查看生效值
./rk3528-sdk.sh --conf ./custom.conf fw-build all
RK_WORKSPACE=/mnt/data/rk3528 ./rk3528-sdk.sh fw-build all
```

## 常用变量

`RK_WORKSPACE`、`RK_DOWNLOAD_DIR`、`RK_OUTPUT_DIR`、`RK_LOG_DIR`、`RK_JOBS`、
`RK_DEFAULT_OS`、`RK_TOOLCHAIN_BIN`、`RK_MIN_FREE_GB`、
`RK_GITHUB_MIRROR` / `RK_RAW_MIRROR`（国内加速）。

路线 D（W132D 主线 Linux）的配置集中在 `sdk.conf` 末尾的 `RK_W132D_*` 段：上游仓库、
分支、Release 地址、Python 版本要求与最小磁盘空间；详见
[docs/10-W132D主线Linux.md](../docs/10-W132D主线Linux.md)。

完整清单见 [docs/06-命令参考.md](../docs/06-命令参考.md)。
