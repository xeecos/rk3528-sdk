#!/usr/bin/env bash
# 检查（可选安装）编译主机环境
# 支持平台: 原生 Ubuntu 20.04/22.04/24.04 x86_64 / Win11 WSL2 中的 Ubuntu
# 用法: check-host.sh [--install] [--yes]
# ==============================================================================
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/config.sh"

DO_INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --install) DO_INSTALL=1 ;;
        --yes)     export RK_ASSUME_YES=1 ;;
        *)         : ;;
    esac
done

require_linux
require_not_root

log_step "主机信息"
if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    log_info "发行版: ${PRETTY_NAME:-unknown}"
    OS_ID="${ID:-unknown}"
    OS_VER="${VERSION_ID:-0}"
else
    OS_ID=unknown; OS_VER=0
fi
log_info "架构: $(uname -m)    内核: $(uname -r)"
log_info "CPU: $(jobs_count) 线程可用    内存: $(free -h 2>/dev/null | awk '/^Mem:/{print $2}' || echo '?')"

# ------------------------------------------------------------------------------
# 平台支持矩阵：仅「原生 Ubuntu x86_64」与「Windows WSL2 中的 Ubuntu」
# 识别逻辑统一放在 lib/common.sh 的 detect_platform()，所有脚本共用；
# WSL1 / 非 Linux 的硬拦截已由 require_linux 完成，这里只负责展示与针对性提示。
# ------------------------------------------------------------------------------
PLATFORM="$(detect_platform)"
IS_WSL2=0
if [[ "$PLATFORM" == "wsl2" ]]; then
    IS_WSL2=1
fi
if [[ "$(uname -m)" != "x86_64" ]]; then
    log_warn "架构 $(uname -m) 不在支持范围（仅 x86_64）；可继续但结果不保证、兼容问题不修复"
fi
if [[ "$OS_ID" != "ubuntu" ]]; then
    log_warn "发行版 ${PRETTY_NAME:-$OS_ID} 不在支持范围（仅 Ubuntu 20.04/22.04/24.04）；apt 依赖安装可能失败"
fi

if (( IS_WSL2 )); then
    if [[ "$OS_ID" == "ubuntu" ]]; then
        log_ok "平台: Windows WSL2 / ${PRETTY_NAME:-Ubuntu}（受支持）"
    else
        log_warn "平台: Windows WSL2 / ${PRETTY_NAME:-$OS_ID}（非目标发行版，不保证；建议 Ubuntu 22.04）"
    fi
    case "$RK_WORKSPACE" in
        /mnt/*)
            log_warn "RK_WORKSPACE=$RK_WORKSPACE 位于 drvfs！必须改到 WSL2 原生 ext4
  （cp config/sdk.wsl.conf.example config/sdk.local.conf），否则 ext4 rootfs 镜像会损坏且编译极慢"
            ;;
        *) log_ok "工作区路径: $RK_WORKSPACE" ;;
    esac
    if [[ ! -e /dev/loop-control ]]; then
        log_warn "未发现 /dev/loop-control：打 eMMC 卡刷固件可能需要 loop 设备，见 docs/09"
    fi
    log_info "烧录 SD 卡 / 线刷请回 Windows 侧（wsl --mount 不支持 SD/USB 读卡器）"
else
    if [[ "$PLATFORM" == "linux" && "$OS_ID" == "ubuntu" ]]; then
        log_ok "平台: 原生 Linux / ${PRETTY_NAME:-Ubuntu}（受支持）"
    else
        log_warn "平台: ${PRETTY_NAME:-$OS_ID}（${PLATFORM}，非目标平台，不保证）"
    fi
fi

if [[ "$OS_ID" == "ubuntu" && "${OS_VER%%.*}" =~ ^[0-9]+$ ]] && (( ${OS_VER%%.*} < 20 )); then
    die "Ubuntu 18.04 及更早版本缺少 lz4 包，官方明确不支持；请升级到 20.04+"
fi

# ------------------------------------------------------------------------------
# 依赖包：分为基础工具与 OpenWrt/内核编译工具
# ------------------------------------------------------------------------------
BASE_PKGS=(git curl wget ca-certificates make gcc g++ build-essential file \
    tar xz-utils gzip bzip2 unzip zip p7zip-full rsync sudo kmod binutils \
    cpio squashfs-tools dosfstools e2fsprogs exfatprogs parted lz4 u-boot-tools \
    device-tree-compiler libncurses-dev libssl-dev libelf-dev zlib1g-dev \
    flex bison gawk gettext patch python3 python3-setuptools \
    libglib2.0-dev subversion texinfo xmlto libtool autoconf automake \
    pkg-config ninja-build cmake bc qemu-utils util-linux)

# 32 位兼容库仅 x86_64（受支持架构）可用；非 x86_64 平台跳过，避免 apt 找不到包
MULTILIB_PKGS=()
[[ "$(uname -m)" == "x86_64" ]] && MULTILIB_PKGS=(lib32gcc-s1 libc6-dev-i386 gcc-multilib g++-multilib)

# 命令 -> 包名（用于逐项报告缺失）
declare -A CMD2PKG=(
    [git]=git [curl]=curl [wget]=wget [make]=make [gcc]=gcc [g++]=g++
    [python3]=python3 [xz]=xz-utils [unzip]=unzip [rsync]=rsync
    [parted]=parted [lz4]=lz4 [mkimage]=u-boot-tools [dtc]=device-tree-compiler
    [flex]=flex [bison]=bison [gawk]=gawk [msgfmt]=gettext [cpio]=cpio
    [mksquashfs]=squashfs-tools [depmod]=kmod [strip]=binutils
)

log_step "必需命令检查"
missing=()
for c in git curl wget make gcc g++ python3 xz unzip rsync parted lz4 mkimage dtc flex bison gawk msgfmt cpio mksquashfs depmod strip; do
    if have_cmd "$c"; then
        printf '  %s[OK]%s    %-14s (%s)\n' "$C_GREEN" "$C_OFF" "$c" "${CMD2PKG[$c]:-}"
    else
        printf '  %s[缺失]%s %-14s (%s)\n' "$C_YELLOW" "$C_OFF" "$c" "${CMD2PKG[$c]:-}"
        missing+=("$c")
    fi
done

log_step "磁盘空间"
check_free_gb "$RK_WORKSPACE" "${RK_MIN_FREE_GB}" || \
    log_warn "空间检查未通过；全量编译 FriendlyWrt 通常需要 50GB 以上，建议扩容后继续"

log_step "交叉编译工具链"
if [[ -x "${RK_TOOLCHAIN_BIN}/${RK_CROSS_COMPILE}gcc" ]]; then
    "${RK_TOOLCHAIN_BIN}/${RK_CROSS_COMPILE}gcc" --version | head -1
    log_ok "工具链就绪: $RK_TOOLCHAIN_BIN"
else
    log_warn "未安装 ${RK_TOOLCHAIN_VERSION} 工具链，请执行: ./rk3528-sdk.sh install-toolchain"
fi

if (( DO_INSTALL )); then
    if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" && "${RK_DRY_RUN:-0}" != "1" ]]; then
        die "--install 仅支持 apt 系发行版，请手工安装以下软件包: ${BASE_PKGS[*]}"
    fi
    log_step "安装依赖（需要 sudo）"
    have_cmd sudo || die "缺少 sudo"
    if ! confirm "将执行 apt-get update 并安装约 50 个编译依赖包，继续?"; then
        die "已取消"
    fi
    run sudo apt-get update
    # 一次性安装；若某个包在当前发行版不可用，回退为逐包安装并跳过失败项
    if ! run sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
            --no-install-recommends "${BASE_PKGS[@]}" "${MULTILIB_PKGS[@]}"; then
        log_warn "批量安装未完全成功，改为逐包安装（缺失包会被跳过并列出）"
        local_failed=()
        for p in "${BASE_PKGS[@]}" "${MULTILIB_PKGS[@]}"; do
            run sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
                --no-install-recommends "$p" >/dev/null 2>&1 || local_failed+=("$p")
        done
        if ((${#local_failed[@]})); then
            log_warn "以下包未能安装（多数为可选）: ${local_failed[*]}"
        fi
    fi
    log_ok "依赖安装完成"
    echo
    log_info "请重新运行 ./rk3528-sdk.sh check-host 确认无缺失项"
elif ((${#missing[@]})); then
    echo
    log_warn "有 ${#missing[@]} 项依赖缺失，可执行："
    printf '  ./rk3528-sdk.sh check-host --install\n\n'
else
    log_ok "主机依赖检查通过"
fi
