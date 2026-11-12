# lib/

公共 Bash 函数库，**不会被直接执行**，由 `rk3528-sdk.sh` 与 `scripts/*.sh` 通过 `source` 加载。

| 文件 | 职责 |
|---|---|
| `common.sh` | 日志输出、平台/权限检查、命令执行与预演、下载与 git 封装、磁盘检查、交互确认 |
| `config.sh` | 推导 `RK_ROOT`、按优先级加载配置、派生路径、设置工具链 PATH、打印配置 |

## 二次开发

新增子脚本时，在开头加上这一行即可获得全部公共能力：

```bash
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/config.sh"
```

`config.sh` 会自动 `source common.sh`，并统一启用 `set -euo pipefail`。

## 常用函数

| 分类 | 函数 |
|---|---|
| 日志 | `log_info` `log_ok` `log_warn` `log_error` `log_step` `die` |
| 检查 | `have_cmd` `need_cmd` `need_cmds` `require_linux` `require_root` `require_not_root` `require_dir` `require_file` `check_free_gb` `validate_os` |
| 执行 | `run` `run_in` `run_sh` `run_in_logged`（`RK_DRY_RUN=1` 时统一只打印） |
| 文件 | `ensure_dir` `download` `git_clone` |
| 交互 | `confirm` `confirm_dangerous`（危险操作必须手工输入确认串） |
| 平台 | `detect_platform`（返回 `wsl1` / `wsl2` / `linux` / `other`）、`require_linux` |
| 其它 | `jobs_count` `setup_toolchain_path` `print_config` `show_block_devices` |

约定：内部变量统一 `RK_` 前缀；所有耗时构建命令通过 `run_in_logged` 同步写日志到 `logs/`。

**平台口径**：只支持原生 Ubuntu 20.04/22.04/24.04 **x86_64** 与 Win11 **WSL2** 中的 Ubuntu
（见根 README §3）。所有脚本都通过 `source lib/config.sh` → `require_linux` 统一检查：
`wsl1` 与 `other` 直接拒绝，非 x86_64 / 非 Ubuntu 只由 `check-host` 警告、不硬拦。
非目标平台/CI 仍可用 `RK_ALLOW_NON_LINUX=1` 预演，但这不代表承诺支持。
