#!/usr/bin/env bash
# ==============================================================================
# 配置加载与派生路径。用法（每个脚本开头）：
#   source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/config.sh"
# 加载优先级：config/sdk.conf -> config/sdk.local.conf -> $RK_CONF -> 环境变量
#
# 平台口径：只支持原生 Ubuntu 20.04/22.04/24.04 x86_64 与 Win11 WSL2 中的 Ubuntu。
# 所有脚本加载本文件后必须调用 require_linux（统一在 common.sh 做 WSL1 / 非 Linux 拦截）。
# ==============================================================================

_LIB_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
export RK_ROOT="$(cd "${_LIB_DIR}/.." && pwd)"

# shellcheck source=common.sh
source "${_LIB_DIR}/common.sh"

_CONF_DEFAULT="${RK_ROOT}/config/sdk.conf"
_CONF_LOCAL="${RK_ROOT}/config/sdk.local.conf"

[[ -f "$_CONF_DEFAULT" ]] || die "配置文件缺失: $_CONF_DEFAULT"
# shellcheck source=/dev/null
source "$_CONF_DEFAULT"
if [[ -f "$_CONF_LOCAL" ]]; then
    log_info "加载本机配置: $_CONF_LOCAL"
    # shellcheck source=/dev/null
    source "$_CONF_LOCAL"
fi
if [[ -n "${RK_CONF:-}" ]]; then
    [[ -f "$RK_CONF" ]] || die "RK_CONF 指向的文件不存在: $RK_CONF"
    log_info "加载指定配置: $RK_CONF"
    # shellcheck source=/dev/null
    source "$RK_CONF"
fi

# ------------------------------------------------------------------------------
# 派生目录（可用同名环境变量覆盖）
# ------------------------------------------------------------------------------
export RK_FW_DIR="${RK_FW_DIR:-${RK_WORKSPACE}/friendlywrt25-rk3528}"
export RK_SDFUSE_DIR="${RK_SDFUSE_DIR:-${RK_WORKSPACE}/sd-fuse_rk3528}"
export RK_KERNEL_SRC="${RK_KERNEL_SRC:-${RK_WORKSPACE}/kernel-rockchip}"
export RK_UBOOT_SRC="${RK_UBOOT_SRC:-${RK_WORKSPACE}/uboot-rockchip}"
export RK_RKBIN_SRC="${RK_RKBIN_SRC:-${RK_WORKSPACE}/rkbin}"
export RK_PREBUILTS_SRC="${RK_PREBUILTS_SRC:-${RK_WORKSPACE}/prebuilts}"
# 路线 D：ZTE W132D 主线 Linux（独立上游仓库）
export RK_W132D_DIR="${RK_W132D_DIR:-${RK_WORKSPACE}/w132d-linux-mainline}"
export RK_W132D_FLASH_DIR="${RK_W132D_FLASH_DIR:-${RK_DOWNLOAD_DIR}/w132d-flash}"
export RK_TOOLCHAIN_BIN="${RK_TOOLCHAIN_BIN:-${RK_TOOLCHAIN_ROOT}/${RK_TOOLCHAIN_VERSION}/bin}"
export RK_KERNEL_IMG_OUT="${RK_KERNEL_IMG_OUT:-${RK_OUTPUT_DIR}/manual-kernel}"
export RK_UBOOT_IMG_OUT="${RK_UBOOT_IMG_OUT:-${RK_OUTPUT_DIR}/manual-uboot}"

# 供 sd-fuse 使用的非交互开关
export SDFUSE_NONINTERACTIVE="${RK_SDFUSE_NONINTERACTIVE}"

# 常用目录在真实执行时创建；预演模式不落盘
if [[ "${RK_DRY_RUN:-0}" != "1" && "${RK_INIT_DIRS:-1}" != "0" ]]; then
    ensure_dir "$RK_WORKSPACE" "$RK_DOWNLOAD_DIR" "$RK_OUTPUT_DIR" "$RK_LOG_DIR"
fi

# 把交叉编译器加入 PATH（若已安装）
setup_toolchain_path() {
    if [[ "${RK_DRY_RUN:-0}" == "1" ]]; then
        log_warn "[预演] 跳过交叉工具链检查"
        return 0
    fi
    if [[ -d "$RK_TOOLCHAIN_BIN" ]]; then
        case ":$PATH:" in
            *":${RK_TOOLCHAIN_BIN}:"*) ;;
            *) export PATH="${RK_TOOLCHAIN_BIN}:$PATH" ;;
        esac
        export CROSS_COMPILE="${RK_CROSS_COMPILE}"
        export ARCH=arm64
        log_ok "工具链已加入 PATH: $RK_TOOLCHAIN_BIN"
    else
        log_warn "工具链目录不存在: $RK_TOOLCHAIN_BIN（可先执行 install-toolchain）"
        return 1
    fi
    if ! have_cmd "${RK_CROSS_COMPILE}gcc"; then
        log_error "未找到 ${RK_CROSS_COMPILE}gcc，请检查工具链安装"
        return 1
    fi
}

# 输出当前生效配置，供 status / 排障使用
print_config() {
    cat <<EOF
  RK_ROOT            = $RK_ROOT
  RK_WORKSPACE       = $RK_WORKSPACE
  RK_DOWNLOAD_DIR    = $RK_DOWNLOAD_DIR
  RK_OUTPUT_DIR      = $RK_OUTPUT_DIR
  RK_TOOLCHAIN_BIN   = $RK_TOOLCHAIN_BIN
  RK_CROSS_COMPILE   = $RK_CROSS_COMPILE
  RK_JOBS            = $(jobs_count)
  RK_DEFAULT_OS      = $RK_DEFAULT_OS
  RK_DRY_RUN         = ${RK_DRY_RUN:-0}
  RK_FW_DIR          = $RK_FW_DIR
  RK_SDFUSE_DIR      = $RK_SDFUSE_DIR
  RK_KERNEL_SRC      = $RK_KERNEL_SRC ($RK_KERNEL_BRANCH)
  RK_UBOOT_SRC       = $RK_UBOOT_SRC ($RK_UBOOT_BRANCH)
  RK_SDFUSE_BRANCH   = $RK_SDFUSE_BRANCH
  RK_W132D_DIR       = $RK_W132D_DIR ($RK_W132D_BRANCH)
  RK_W132D_FLASH_DIR = $RK_W132D_FLASH_DIR
EOF
}
