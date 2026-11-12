#!/usr/bin/env bash
# 手工编译内核 linux-v6.1.y 并打包 kernel.img / resource.img
# 对应 WiKi「编译内核linux-v6.1.y」，适用于：
#   friendlywrt25 / friendlywrt25-docker / ubuntu-noble-core-arm64
#   openmediavault-arm64 / debian-trixie-core-arm64
#
# 用法: kernel-build.sh [--friendlywrt] [--menuconfig] [--pack-only]
#                       [--defconfig NAME] [--jobs N] [--no-clone] [--yes]
# ==============================================================================
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/config.sh"

FRIENDLYWRT_CFG=0
MENUCONFIG=0
PACK_ONLY=0
NO_CLONE=0
DEFCONFIG="$RK_KERNEL_DEFCONFIG"
JOBS="$(jobs_count)"
while (($#)); do
    case "$1" in
        --friendlywrt) FRIENDLYWRT_CFG=1 ;;
        --menuconfig)  MENUCONFIG=1 ;;
        --pack-only)   PACK_ONLY=1 ;;
        --no-clone)    NO_CLONE=1 ;;
        --defconfig)   shift; DEFCONFIG="${1:?--defconfig 缺少参数}" ;;
        --jobs)        shift; JOBS="${1:?--jobs 缺少参数}" ;;
        --yes)         export RK_ASSUME_YES=1 ;;
        -h|--help)
            sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) die "未知参数: $1" ;;
    esac
    shift
done

require_linux
require_not_root
need_cmds git make curl tar find xargs
setup_toolchain_path || die "请先执行 ./rk3528-sdk.sh install-toolchain"

SRC="$RK_KERNEL_SRC"
PACKDIR="$RK_KERNEL_IMG_OUT"
TOOLDIR="${RK_DOWNLOAD_DIR}/tools"
MAKE_ARGS=(CROSS_COMPILE="$RK_CROSS_COMPILE" ARCH=arm64)

log_step "编译参数"
log_info "源码目录  : $SRC ($RK_KERNEL_BRANCH)"
log_info "defconfig : $DEFCONFIG$([[ $FRIENDLYWRT_CFG -eq 1 ]] && echo " + $RK_KERNEL_EXTRA_CONFIG")"
log_info "线程数    : $JOBS"
log_info "产物目录  : $PACKDIR"

ensure_dir "$PACKDIR" "$TOOLDIR"

# ------------------------------------------------------------------------------
# 1. 源码
# ------------------------------------------------------------------------------
if (( NO_CLONE )); then
    require_dir "$SRC"
elif (( PACK_ONLY )); then
    require_dir "$SRC"
else
    log_step "下载内核源码"
    git_clone "$RK_KERNEL_REPO" "$SRC" "$RK_KERNEL_BRANCH" 1
fi

# ------------------------------------------------------------------------------
# 2. 配置 + 编译
# ------------------------------------------------------------------------------
if (( ! PACK_ONLY )); then
    log_step "配置内核"
    run_in "$SRC" touch .scmversion
    CFGS=("$DEFCONFIG")
    (( FRIENDLYWRT_CFG )) && CFGS+=("$RK_KERNEL_EXTRA_CONFIG")
    run_in "$SRC" make "${MAKE_ARGS[@]}" "${CFGS[@]}"
    if (( MENUCONFIG )); then
        log_step "启动 menuconfig（交互界面）"
        run_in "$SRC" make "${MAKE_ARGS[@]}" menuconfig
        log_info "如需保存自定义配置：make savedefconfig 后把 defconfig 放到 arch/arm64/configs/"
    fi

    check_free_gb "$RK_WORKSPACE" 10 || log_warn "空间偏低，内核编译可能失败"

    log_step "编译内核 Image"
    run_in_logged "$SRC" "${RK_LOG_DIR}/kernel-build-$(date +%Y%m%d-%H%M%S).log" \
        make "${MAKE_ARGS[@]}" -j"$JOBS"

    log_step "编译并安装驱动模块到 out-modules"
    if [[ "${RK_DRY_RUN:-0}" != "1" ]]; then
        mkdir -p "$SRC/out-modules"
        # 只清理 out-modules 内部，不动源码其它内容
        find "$SRC/out-modules" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    fi
    run_in_logged "$SRC" "${RK_LOG_DIR}/kernel-modules-$(date +%Y%m%d-%H%M%S).log" \
        make "${MAKE_ARGS[@]}" INSTALL_MOD_PATH="$SRC/out-modules" modules -j"$JOBS"
    run_in "$SRC" make "${MAKE_ARGS[@]}" INSTALL_MOD_PATH="$SRC/out-modules" modules_install

    if [[ "${RK_DRY_RUN:-0}" != "1" ]]; then
        KVER=$(cd "$SRC" && make "${MAKE_ARGS[@]}" kernelrelease 2>/dev/null | tail -1)
        log_info "内核版本: $KVER"
        if [[ ! -f "$SRC/out-modules/lib/modules/${KVER}/modules.dep" ]]; then
            DEPMOD=$(command -v depmod || echo /sbin/depmod)
            [[ -x "$DEPMOD" ]] || die "找不到 depmod（安装 kmod 包）"
            run_in "$SRC" "$DEPMOD" -b "$SRC/out-modules" \
                -E Module.symvers -F System.map -w "$KVER"
        fi
        STRIP="${RK_CROSS_COMPILE}strip"
        have_cmd "$STRIP" || die "找不到 $STRIP，请检查工具链 PATH"
        run_sh "cd $(printf '%q' "$SRC/out-modules") && find . -name '*.ko' -print0 | xargs -0 -r $(printf '%q' "$STRIP") --strip-unneeded"
        # 把模块目录打包，便于上传到目标板替换 /lib/modules
        run tar czf "$PACKDIR/kernel-modules-${KVER}.tar.gz" -C "$SRC/out-modules" .
    fi
fi

# ------------------------------------------------------------------------------
# 3. 打包 kernel.img 与 resource.img
# ------------------------------------------------------------------------------
log_step "准备打包工具（来自 sd-fuse_rk3528/${RK_SDFUSE_BRANCH}）"
RAW="${RK_RAW_BASE_URL}"
if [[ -n "${RK_RAW_MIRROR:-}" ]]; then
    RAW="${RK_RAW_MIRROR%/}/${RAW}"
fi
# 官方 sd-fuse 同时提供 tools/（x86_64 ELF）与 tools/aarch64/（arm64 ELF）两套打包工具，
# 架构不匹配会报 Exec format error。两个受支持平台均为 x86_64，默认走 tools/。
# 此自动检测只是为非目标平台 / CI 保留的通用实现，不代表承诺支持。
# 可用 RK_SDFUSE_TOOL_ARCH=x86_64|aarch64 强制指定。
TOOL_ARCH="${RK_SDFUSE_TOOL_ARCH:-}"
if [[ -z "$TOOL_ARCH" ]]; then
    case "$(uname -m)" in
        aarch64|arm64) TOOL_ARCH=aarch64 ;;
        *)             TOOL_ARCH=x86_64 ;;
    esac
fi
case "$TOOL_ARCH" in
    aarch64) TOOL_SUBDIR="tools/aarch64" ;;
    x86_64)  TOOL_SUBDIR="tools" ;;
    *) die "RK_SDFUSE_TOOL_ARCH 只能是 x86_64 或 aarch64，当前: $TOOL_ARCH" ;;
esac
log_info "打包工具架构: $TOOL_ARCH ($TOOL_SUBDIR)"
for f in mkkrnlimg resource_tool; do
    download "${RAW}/${TOOL_SUBDIR}/${f}" "${TOOLDIR}/${f}"
done
for f in logo.bmp logo_kernel.bmp; do
    download "${RAW}/prebuilt/boot/${f}" "${TOOLDIR}/${f}"
done
if [[ "${RK_DRY_RUN:-0}" != "1" ]]; then
    chmod 755 "$TOOLDIR/mkkrnlimg" "$TOOLDIR/resource_tool"
    if have_cmd file && ! file "$TOOLDIR/mkkrnlimg" | grep -qi ELF; then
        log_warn "mkkrnlimg 不是 ELF 可执行文件，请确认下载源返回的是二进制而非 HTML"
    fi
fi

log_step "生成 kernel.img / resource.img"
require_file "$SRC/arch/arm64/boot/Image" "（请先完成内核编译）"
run_in "$PACKDIR" "$TOOLDIR/mkkrnlimg" "$SRC/arch/arm64/boot/Image" kernel.img

shopt -s nullglob
DTBS=("$SRC"/arch/arm64/boot/dts/rockchip/rk3528-nanopi*-rev*.dtb)
shopt -u nullglob
if ((${#DTBS[@]} == 0)) && [[ "${RK_DRY_RUN:-0}" != "1" ]]; then
    die "未找到 rk3528-nanopi*-rev*.dtb，请确认内核编译已生成设备树"
fi
# 等价于 WiKi 的 --dtbname <glob> logo.bmp logo_kernel.bmp（shell 展开为多个 dtb）
run_in "$PACKDIR" "$TOOLDIR/resource_tool" --dtbname "${DTBS[@]}" \
    "$TOOLDIR/logo.bmp" "$TOOLDIR/logo_kernel.bmp"

log_step "完成"
cat <<EOF
产物（$PACKDIR）：
  kernel.img                      -> 对应 GPT 分区 6 (kernel)
  resource.img                    -> 对应 GPT 分区 5 (resource)
  kernel-modules-<ver>.tar.gz      -> 解压后替换目标板 /lib/modules

安装方式：
  ./rk3528-sdk.sh install-board             # 目标板上 dd 更新分区
  ./rk3528-sdk.sh flash-loader              # 主机上 upgrade_tool 线刷
  或把两个 img 放入 sd-fuse 的 <OS>/ 目录后重新打包固件

EOF
