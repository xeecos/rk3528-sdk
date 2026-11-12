#!/usr/bin/env bash
# 通过 sd-fuse 编译内核 / 内核头文件 / u-boot，并自动更新 <OS>/ 下的分区镜像
# 对应 WiKi「使用脚本进行编译」章节的 3.2 / 3.3 / 3.4
#
# 用法: sdfuse-build.sh <kernel|headers|uboot> [OS] [选项]
#   --kcfg NAME       指定内核 defconfig（sd-fuse 的 KCFG）
#   --no-clone        使用已有源码目录，不重新 clone
#   --no-third-party  跳过第三方驱动（BUILD_THIRD_PARTY_DRIVER=0）
#   --skip-distclean  编译前不执行 distclean（SKIP_DISTCLEAN=1）
# ==============================================================================
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/config.sh"

usage() {
    cat <<EOF
用法: ./rk3528-sdk.sh sdfuse-build <kernel|headers|uboot> [OS]
  kernel   编译内核并更新 <OS>/ 下的 kernel.img、resource.img 与 rootfs.img 中的模块
  headers  仅编译内核头文件 deb（MK_HEADERS_DEB=1 BUILD_THIRD_PARTY_DRIVER=0）
  uboot    编译 u-boot 并更新 <OS>/ 下的 uboot.img / trust.img / MiniLoaderAll.bin
OS 省略时使用 ${RK_DEFAULT_OS}。
EOF
}

(($#)) || { usage; exit 1; }
ACTION=$1; shift
OS=""
KCFG=""
NO_CLONE=0
NO_THIRD_PARTY=0
SKIP_DISTCLEAN=0
while (($#)); do
    case "$1" in
        --kcfg) shift; KCFG="${1:?--kcfg 缺少参数}" ;;
        --no-clone) NO_CLONE=1 ;;
        --no-third-party) NO_THIRD_PARTY=1 ;;
        --skip-distclean) SKIP_DISTCLEAN=1 ;;
        --yes) export RK_ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        -*) die "未知参数: $1" ;;
        *) [[ -z "$OS" ]] || die "多余的 OS 参数: $1"; OS="$1" ;;
    esac
    shift
done
OS="${OS:-$RK_DEFAULT_OS}"
validate_os "$OS"
[[ "$ACTION" =~ ^(kernel|headers|uboot)$ ]] || die "未知动作: $ACTION（可用 kernel / headers / uboot）"

require_linux
require_not_root
need_cmds git

DIR="$RK_SDFUSE_DIR"
require_dir "$DIR" "（请先执行 ./rk3528-sdk.sh sdfuse-init）"
require_dir "$DIR/$OS" "（缺少分区镜像目录，请先执行 sdfuse-init $OS）"
require_file "$DIR/build-kernel.sh" "（sd-fuse 源码不完整）"

log_step "sd-fuse 编译：$ACTION / $OS"
log_info "脚本目录: $DIR"
log_info "OS 目录 : $DIR/$OS"
log_info "非交互  : SDFUSE_NONINTERACTIVE=${SDFUSE_NONINTERACTIVE:-}"
check_free_gb "$RK_WORKSPACE" 20 || log_warn "空间偏低，内核编译通常需要 20GB 以上"

# 构造 sd-fuse 环境变量前缀
ENVV=(env "SDFUSE_NONINTERACTIVE=${SDFUSE_NONINTERACTIVE:-y}")
[[ -n "$KCFG" ]]            && ENVV+=("KCFG=$KCFG")
(( NO_THIRD_PARTY ))         && ENVV+=("BUILD_THIRD_PARTY_DRIVER=0")
(( SKIP_DISTCLEAN ))         && ENVV+=("SKIP_DISTCLEAN=1")
LOGFILE="${RK_LOG_DIR}/sdfuse-${ACTION}-${OS}-$(date +%Y%m%d-%H%M%S).log"

case "$ACTION" in
    kernel)
        if (( NO_CLONE )); then
            require_dir "$RK_KERNEL_SRC"
        else
            log_step "下载内核源码 $RK_KERNEL_BRANCH"
            git_clone "$RK_KERNEL_REPO" "$RK_KERNEL_SRC" "$RK_KERNEL_BRANCH" 1
        fi
        ENVV+=("KERNEL_SRC=$RK_KERNEL_SRC")
        log_info "KERNEL_SRC=$RK_KERNEL_SRC"
        (( NO_THIRD_PARTY )) || log_info "默认会一并编译第三方驱动；跳过请加 --no-third-party"
        run_in_logged "$DIR" "$LOGFILE" "${ENVV[@]}" ./build-kernel.sh "$OS"
        ;;
    headers)
        if (( NO_CLONE )); then
            require_dir "$RK_KERNEL_SRC"
        else
            log_step "下载内核源码 $RK_KERNEL_BRANCH"
            git_clone "$RK_KERNEL_REPO" "$RK_KERNEL_SRC" "$RK_KERNEL_BRANCH" 1
        fi
        # WiKi: MK_HEADERS_DEB=1 BUILD_THIRD_PARTY_DRIVER=0 KERNEL_SRC=... ./build-kernel.sh <OS>
        ENVV+=("KERNEL_SRC=$RK_KERNEL_SRC" "MK_HEADERS_DEB=1" "BUILD_THIRD_PARTY_DRIVER=0")
        run_in_logged "$DIR" "$LOGFILE" "${ENVV[@]}" ./build-kernel.sh "$OS"
        ;;
    uboot)
        if (( NO_CLONE )); then
            require_dir "$RK_UBOOT_SRC"
        else
            log_step "下载 u-boot 源码 $RK_UBOOT_BRANCH"
            git_clone "$RK_UBOOT_REPO" "$RK_UBOOT_SRC" "$RK_UBOOT_BRANCH" 1
        fi
        ENVV+=("UBOOT_SRC=$RK_UBOOT_SRC")
        log_info "UBOOT_SRC=$RK_UBOOT_SRC"
        run_in_logged "$DIR" "$LOGFILE" "${ENVV[@]}" ./build-uboot.sh "$OS"
        ;;
esac

log_ok "$ACTION 完成，$DIR/$OS 下的分区镜像已被更新"
log_info "日志: $LOGFILE"
log_info "下一步: ./rk3528-sdk.sh sdfuse-image sd $OS"
