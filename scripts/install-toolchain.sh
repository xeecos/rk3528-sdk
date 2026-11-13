#!/usr/bin/env bash
# 安装 11.3-aarch64 交叉编译工具链到 /opt/FriendlyARM/toolchain
# 官方方式：git clone friendlyarm/prebuilts -> sudo tar xf toolchain-11.3-aarch64.tar.xz -C /
# 用法: install-toolchain.sh [--package FILE] [--force] [--yes]
# ==============================================================================
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/config.sh"

PKG=""
FORCE=0
while (($#)); do
    case "$1" in
        --package) shift; [[ $# -gt 0 ]] || die "--package 缺少参数"; PKG="$1" ;;
        --package=*) PKG="${1#*=}" ;;
        --force) FORCE=1 ;;
        --yes) export RK_ASSUME_YES=1 ;;
        -h|--help)
            echo "用法: install-toolchain.sh [--package FILE] [--force]"
            echo "  --package FILE  使用本地 toolchain-11.3-aarch64.tar.xz，跳过 git clone"
            echo "  --force         已安装时也重新解压"
            exit 0 ;;
        *) die "未知参数: $1" ;;
    esac
    shift
done

require_linux
require_not_root

GCC="${RK_TOOLCHAIN_BIN}/${RK_CROSS_COMPILE}gcc"
if [[ -x "$GCC" && "$FORCE" -eq 0 ]]; then
    log_ok "工具链已安装: $GCC"
    "$GCC" --version | head -1
    log_info "编译时请保证 ${RK_TOOLCHAIN_BIN} 在 PATH 中（本工具会自动设置）"
    exit 0
fi

# 1) 取得工具链压缩包
if [[ -z "$PKG" ]]; then
    if [[ -n "${RK_TOOLCHAIN_URL:-}" ]]; then
        PKG="${RK_DOWNLOAD_DIR}/toolchain-${RK_TOOLCHAIN_VERSION}.tar.xz"
        download "$RK_TOOLCHAIN_URL" "$PKG"
    else
        log_step "从 friendlyarm/prebuilts 获取工具链"
        log_warn "prebuilts 仓库包含多套预编译工具链，clone 可能需要数 GB 空间与较长时间"
        log_info "若网速受限，可从网盘单独下载 toolchain-11.3-aarch64.tar.xz 后用 --package 指定"
        git_clone "$RK_PREBUILTS_REPO" "$RK_PREBUILTS_SRC" "$RK_PREBUILTS_BRANCH" 1
        PKG="${RK_PREBUILTS_SRC}/gcc-x64/toolchain-${RK_TOOLCHAIN_VERSION}.tar.xz"
        require_file "$PKG" "（也可设置 RK_TOOLCHAIN_URL 直接下载，或用 --package 指定本地文件）"
    fi
fi
require_file "$PKG" "（可用 --package 指定绝对路径）"

# 2) 解压到 /
log_step "解压工具链到 /"
if [[ ! "${RK_TOOLCHAIN_ROOT}" == /opt/FriendlyARM/toolchain ]]; then
    log_warn "RK_TOOLCHAIN_ROOT=$RK_TOOLCHAIN_ROOT 与官方包内路径不一致；官方 tar 固定解压到 /opt/FriendlyARM/toolchain"
fi
if ! confirm "即将执行 sudo tar xf $(basename "$PKG") -C / ，需要管理员权限，继续?"; then
    die "已取消"
fi
run sudo tar xf "$PKG" -C /

# 3) 校验（预演模式下跳过）
if [[ "${RK_DRY_RUN:-0}" == "1" ]]; then
    log_ok "[预演] 完成，实际执行后会校验 ${GCC}"
    exit 0
fi
if [[ -x "$GCC" ]]; then
    log_ok "安装成功: $GCC"
    "$GCC" --version | head -1
else
    log_error "解压后未在 ${RK_TOOLCHAIN_BIN} 找到 ${RK_CROSS_COMPILE}gcc"
    log_info "请检查 /opt/FriendlyARM/toolchain 下的实际目录名，并通过 RK_TOOLCHAIN_VERSION / RK_TOOLCHAIN_BIN 指定"
    if [[ -d /opt/FriendlyARM/toolchain ]]; then
        log_info "当前已存在的工具链目录："
        ls -1 /opt/FriendlyARM/toolchain
    fi
    exit 1
fi

cat <<EOF

${C_BOLD}手工编译时请执行（本工具的其它脚本会自动设置）：${C_OFF}
  export PATH=${RK_TOOLCHAIN_BIN}:\$PATH
  export CROSS_COMPILE=${RK_CROSS_COMPILE}
  export ARCH=arm64

EOF
