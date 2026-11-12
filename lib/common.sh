#!/usr/bin/env bash
# ==============================================================================
# 公共函数库：日志、检查、命令执行、下载、git 封装
# 被所有 scripts/*.sh 与入口脚本 source，不单独执行。
# ==============================================================================

# shellcheck disable=SC2034
set -euo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''; C_BOLD=''; C_OFF=''
fi

log_info()  { printf '%s[INFO]%s  %s\n'  "${C_BLUE}"   "${C_OFF}" "$*"; }
log_ok()    { printf '%s[ OK ]%s  %s\n'  "${C_GREEN}"  "${C_OFF}" "$*"; }
log_warn()  { printf '%s[WARN]%s  %s\n'  "${C_YELLOW}" "${C_OFF}" "$*" >&2; }
log_error() { printf '%s[FAIL]%s  %s\n'  "${C_RED}"    "${C_OFF}" "$*" >&2; }
log_step()  { printf '\n%s>>> %s%s\n'    "${C_BOLD}${C_CYAN}" "$*" "${C_OFF}"; }
log_die()   { log_error "$*"; exit 1; }
die()       { log_error "$*"; exit 1; }

# 打印错误发生位置，便于排查
if [[ "${RK_DEBUG:-0}" == "1" ]]; then
    trap 'log_error "脚本在第 ${LINENO} 行失败: ${BASH_COMMAND}"' ERR
fi

have_cmd()  { command -v "$1" >/dev/null 2>&1; }
need_cmd()  { have_cmd "$1" || die "缺少命令 '$1'，请先执行: ./rk3528-sdk.sh check-host --install"; }
need_cmds() { local c; for c in "$@"; do need_cmd "$c"; done; }

# 统一命令执行入口；RK_DRY_RUN=1 时只打印不执行
run() {
    if [[ "${RK_DRY_RUN:-0}" == "1" ]]; then
        printf '%s[DRY-RUN]%s ' "${C_YELLOW}" "${C_OFF}"
        printf '%q ' "$@"
        printf '\n'
        return 0
    fi
    log_info "执行: $*"
    "$@"
}

# 在指定目录执行命令
run_in() {
    local dir=$1; shift
    if [[ ! -d "$dir" ]]; then
        if [[ "${RK_DRY_RUN:-0}" == "1" ]]; then
            log_warn "[预演] 目录尚不存在: $dir"
        else
            die "目录不存在: $dir"
        fi
    fi
    if [[ "${RK_DRY_RUN:-0}" == "1" ]]; then
        printf '%s[DRY-RUN]%s (cd %q && ' "${C_YELLOW}" "${C_OFF}" "$dir"
        printf '%q ' "$@"
        printf ')\n'
        return 0
    fi
    log_info "执行: (cd $dir && $*)"
    ( cd "$dir" && "$@" )
}

# 在指定目录执行并同时写入日志（pipefail 保证失败能被捕获）
# 注意：交互式 ncurses 程序（menuconfig）不要用这个，改用 run_in
run_in_logged() {
    local dir=$1 log=$2; shift 2
    if [[ ! -d "$dir" ]]; then
        if [[ "${RK_DRY_RUN:-0}" == "1" ]]; then
            log_warn "[预演] 目录尚不存在: $dir"
        else
            die "目录不存在: $dir"
        fi
    fi
    if [[ "${RK_DRY_RUN:-0}" == "1" ]]; then
        printf '%s[DRY-RUN]%s (cd %q && ' "${C_YELLOW}" "${C_OFF}" "$dir"
        printf '%q ' "$@"
        printf ') 2>&1 | tee -a %q\n' "$log"
        return 0
    fi
    ensure_dir "$(dirname "$log")"
    log_info "执行: (cd $dir && $*)   日志: $log"
    ( cd "$dir" && "$@" ) 2>&1 | tee -a "$log"
}

# 需要 shell 语法（管道、重定向、glob）时使用，调用方负责引号安全
run_sh() {
    if [[ "${RK_DRY_RUN:-0}" == "1" ]]; then
        printf '%s[DRY-RUN]%s bash -c %q\n' "${C_YELLOW}" "${C_OFF}" "$1"
        return 0
    fi
    log_info "执行: $1"
    bash -c "$1"
}

ensure_dir() {
    local d
    for d in "$@"; do
        [[ -d "$d" ]] && continue
        if [[ "${RK_DRY_RUN:-0}" == "1" ]]; then
            log_warn "[预演] 将创建目录: $d"
            continue
        fi
        log_info "创建目录: $d"
        mkdir -p "$d"
    done
}

# 前置文件/目录检查；预演模式下只告警，让整条命令链能完整打印出来
require_dir() {
    local d=$1 hint=${2:-}
    if [[ -d "$d" ]]; then return 0; fi
    if [[ "${RK_DRY_RUN:-0}" == "1" ]]; then
        log_warn "[预演] 目录尚不存在，实际执行时需先准备: $d"
        return 0
    fi
    die "目录不存在: $d ${hint}"
}

require_file() {
    local f=$1 hint=${2:-}
    if [[ -f "$f" ]]; then return 0; fi
    if [[ "${RK_DRY_RUN:-0}" == "1" ]]; then
        log_warn "[预演] 文件尚不存在，实际执行时需先准备: $f"
        return 0
    fi
    die "文件不存在: $f ${hint}"
}

# 普通确认：RK_ASSUME_YES=1 时自动通过
confirm() {
    local prompt=${1:-"是否继续?"}
    if [[ "${RK_ASSUME_YES:-0}" == "1" ]]; then
        log_warn "自动确认(非交互): $prompt"
        return 0
    fi
    [[ -t 0 ]] || die "需要交互确认但当前非 TTY，请追加 --yes 或设置 RK_ASSUME_YES=1"
    local ans
    read -r -p "${C_YELLOW}${prompt} [y/N] ${C_OFF}" ans
    [[ "$ans" == "y" || "$ans" == "Y" ]]
}

# 危险操作确认：必须显式输入 expected 字符串，--yes 也不能跳过
confirm_dangerous() {
    local expected=$1; shift
    local prompt="$*"
    printf '\n%s%s⚠️  危险操作%s\n' "${C_RED}" "${C_BOLD}" "${C_OFF}"
    printf '%s\n' "$prompt"
    if [[ ! -t 0 ]]; then
        die "危险操作必须在交互式终端执行（当前非 TTY）"
    fi
    local ans
    read -r -p "请输入 '${expected}' 确认: " ans
    [[ "$ans" == "$expected" ]] || die "已取消"
}

# 平台识别：本工具只支持「原生 Ubuntu x86_64」与「Windows WSL2 中的 Ubuntu」。
# 返回 wsl1 | wsl2 | linux | other，供 require_linux / check-host / status 共用，
# 保证所有脚本遵守同一套支持矩阵（见 README §3）。
detect_platform() {
    local krel proc_ver
    krel="$(uname -r 2>/dev/null || true)"
    proc_ver="$(cat /proc/version 2>/dev/null || true)"
    if [[ "$(uname -s 2>/dev/null)" != "Linux" ]]; then
        echo other
    elif [[ -n "${WSL_DISTRO_NAME:-}" || "${proc_ver,,}" == *microsoft* ]]; then
        if [[ "${krel,,}" == *wsl2* || "${proc_ver,,}" == *wsl2* ]]; then
            echo wsl2
        else
            echo wsl1
        fi
    else
        echo linux
    fi
}

require_linux() {
    if [[ "${RK_ALLOW_NON_LINUX:-0}" == "1" ]]; then
        log_warn "已跳过平台检查（RK_ALLOW_NON_LINUX=1）；仅用于预演/测试，不属于受支持平台、不可用于实际编译"
        return 0
    fi
    local p
    p="$(detect_platform)"
    case "$p" in
        wsl1)
            die "检测到 WSL1（内核 $(uname -r)）。本工具只支持 WSL2，请在管理员 PowerShell 执行：
  wsl --set-version <发行版名> 2
  wsl --set-default-version 2
详见 docs/09-WSL2构建指南.md"
            ;;
        other)
            die "当前不是受支持的 Linux 环境（$(uname -s)）。本工具只支持：
  1) 原生 Ubuntu 20.04/22.04/24.04 x86_64
  2) Windows 11 WSL2 中的 Ubuntu 22.04/24.04
Windows 原生 Git Bash / macOS 等不在支持范围；仅需预演可用 RK_ALLOW_NON_LINUX=1 RK_DRY_RUN=1。"
            ;;
    esac
}

require_root() {
    [[ "$(id -u)" -eq 0 ]] || die "该操作需要 root 权限，请使用 sudo 执行"
}

require_not_root() {
    [[ "$(id -u)" -ne 0 ]] || \
        die "请勿用 root 运行编译（OpenWrt 和 sd-fuse 均不允许），请用普通用户执行；仅安装依赖/烧录时需要 sudo"
}

# 剩余空间检查，单位 GB
check_free_gb() {
    local path=${1:-$PWD} need=${2:-${RK_MIN_FREE_GB:-50}}
    if [[ "${RK_DRY_RUN:-0}" == "1" ]]; then
        log_info "[预演] 跳过磁盘空间硬性检查（要求 >= ${need} GB）"
        return 0
    fi
    [[ -e "$path" ]] || path=$(dirname "$path")
    local avail
    avail=$(df -PB1 "$path" 2>/dev/null | awk 'NR==2 {print int($4/1024/1024/1024)}')
    if [[ -z "$avail" ]]; then
        log_warn "无法检测 $path 的可用空间，跳过检查"
        return 0
    fi
    log_info "${path} 可用空间: ${avail} GB (要求 >= ${need} GB)"
    if (( avail < need )); then
        log_warn "磁盘空间不足，可通过 RK_MIN_FREE_GB 调整阈值，或把 RK_WORKSPACE/RK_DOWNLOAD_DIR 指向更大的磁盘"
        return 1
    fi
}

# 下载文件到指定路径（已存在且非空则跳过），可选 sha256 校验
download() {
    local url=$1 dest=$2 sha=${3:-}
    need_cmd curl
    if [[ "${RK_DRY_RUN:-0}" == "1" ]]; then
        printf '%s[DRY-RUN]%s download %q -> %q\n' "${C_YELLOW}" "${C_OFF}" "$url" "$dest"
        return 0
    fi
    ensure_dir "$(dirname "$dest")"
    if [[ -s "$dest" ]]; then
        log_ok "已存在，跳过下载: $dest"
    else
        log_info "下载: $url"
        run curl -fL --retry "${RK_DOWNLOAD_RETRIES:-3}" --retry-delay 3 \
            --connect-timeout 20 -o "${dest}.part" "$url"
        [[ -s "${dest}.part" ]] || die "下载失败: $url"
        mv -f "${dest}.part" "$dest"
        log_ok "下载完成: $dest"
    fi
    if [[ -n "$sha" ]]; then
        echo "${sha}  ${dest}" | sha256sum -c - >/dev/null \
            || die "SHA256 校验失败: $dest"
        log_ok "SHA256 校验通过"
    fi
}

# git clone（已存在则跳过；--update 时执行 fetch + reset）
git_clone() {
    local url=$1 dest=$2 branch=${3:-} depth=${4:-1}
    need_cmd git
    if [[ "${RK_DRY_RUN:-0}" == "1" ]]; then
        printf '%s[DRY-RUN]%s git clone -b %q --depth %q %q %q\n' \
            "${C_YELLOW}" "${C_OFF}" "$branch" "$depth" "$url" "$dest"
        return 0
    fi
    local gh=${RK_GITHUB_MIRROR:-}
    [[ -n "$gh" && "$url" == https://github.com/* ]] && url="${gh%/}/${url}"
    ensure_dir "$(dirname "$dest")"
    if [[ -d "$dest/.git" ]]; then
        log_ok "源码已存在，跳过 clone: $dest"
        if [[ "${RK_GIT_UPDATE:-0}" == "1" && -n "$branch" ]]; then
            run_in "$dest" git fetch --depth "${depth}" origin "$branch"
            run_in "$dest" git reset --hard "FETCH_HEAD"
        fi
        return 0
    fi
    local -a args=(clone --single-branch)
    [[ -n "$branch" ]] && args+=(-b "$branch")
    [[ "$depth" =~ ^[1-9][0-9]*$ ]] && args+=(--depth "$depth")
    args+=("$url" "$dest")
    run git "${args[@]}"
}

# 获取一个可用的 nproc（容器内可能不准，允许 RK_JOBS 覆盖）
jobs_count() {
    local j=${RK_JOBS:-0}
    if [[ ! "$j" =~ ^[0-9]+$ ]] || (( j < 1 )); then
        j=$(nproc 2>/dev/null || echo 4)
    fi
    echo "$j"
}

# 打印分区/块设备信息，供烧录前人工核对
show_block_devices() {
    if have_cmd lsblk; then
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MODEL,MOUNTPOINT
    else
        log_warn "lsblk 不可用，请自行用 fdisk -l 确认设备名"
    fi
}

# 校验 OS 目录名是否在允许列表内
validate_os() {
    local os=$1 list=${2:-${RK_SDFUSE_OS_LIST:-}}
    local item
    for item in $list; do
        [[ "$item" == "$os" ]] && return 0
    done
    log_error "不支持的 OS 名称: '$os'。sd-fuse 对目录名有严格定义，可用值："
    printf '  - %s\n' $list >&2
    exit 1
}

human_size() { du -sh "$1" 2>/dev/null | awk '{print $1}'; }

ts() { date '+%Y-%m-%d %H:%M:%S'; }
