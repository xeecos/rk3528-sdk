#!/usr/bin/env bash
# 手工编译 u-boot v2017.09 并收集产物
# 对应 WiKi「编译u-boot v2017.09」；rkbin 必须与 uboot-rockchip 同级（make.sh 按 ../rkbin 查找）
#
# 用法: uboot-build.sh [--no-clone] [--board NAME] [--yes]
# ==============================================================================
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/config.sh"

NO_CLONE=0
BOARD="$RK_UBOOT_BOARD"
while (($#)); do
    case "$1" in
        --no-clone) NO_CLONE=1 ;;
        --board) shift; BOARD="${1:?--board 缺少参数}" ;;
        --yes) export RK_ASSUME_YES=1 ;;
        -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "未知参数: $1" ;;
    esac
    shift
done

require_linux
require_not_root
need_cmds git make
setup_toolchain_path || die "请先执行 ./rk3528-sdk.sh install-toolchain"

SRC="$RK_UBOOT_SRC"
RKBIN="$RK_RKBIN_SRC"
OUT="$RK_UBOOT_IMG_OUT"

if [[ "$(dirname "$SRC")" != "$(dirname "$RKBIN")" ]]; then
    log_warn "rkbin ($RKBIN) 与 uboot 源码 ($SRC) 不在同级目录，make.sh 可能找不到 rkbin"
fi

log_step "下载源码"
if (( NO_CLONE )); then
    require_dir "$SRC"
    require_dir "$RKBIN"
else
    git_clone "$RK_RKBIN_REPO" "$RKBIN" "$RK_RKBIN_BRANCH" 1
    git_clone "$RK_UBOOT_REPO" "$SRC" "$RK_UBOOT_BRANCH" 1
fi
require_file "$SRC/make.sh" "（源码不完整）"

log_step "编译 u-boot: ./make.sh $BOARD"
run_in_logged "$SRC" "${RK_LOG_DIR}/uboot-build-$(date +%Y%m%d-%H%M%S).log" \
    ./make.sh "$BOARD"

log_step "收集产物到 $OUT"
ensure_dir "$OUT"
if [[ "${RK_DRY_RUN:-0}" != "1" ]]; then
    copied=0
    for f in uboot.img trust.img; do
        if [[ -f "$SRC/$f" ]]; then
            cp -f "$SRC/$f" "$OUT/$f"
            log_ok "$f  ($(du -h "$OUT/$f" | awk '{print $1}'))"
            copied=$((copied + 1))
        else
            log_warn "未找到 $SRC/$f"
        fi
    done
    # SPL loader：打包固件时需改名为 MiniLoaderAll.bin
    loader=$(find "$SRC" -maxdepth 2 -name 'rk*_spl_loader_*.bin' -type f -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | head -1 | cut -d' ' -f2-)
    if [[ -n "$loader" ]]; then
        cp -f "$loader" "$OUT/MiniLoaderAll.bin"
        log_ok "MiniLoaderAll.bin  <- $(basename "$loader")"
        copied=$((copied + 1))
    else
        log_warn "未找到 rk*_spl_loader_*.bin（部分版本由 make.sh 输出到 uboot.img 中，可忽略）"
    fi
    (( copied > 0 )) || die "未收集到任何产物，请检查构建日志"
    echo
    ls -lh "$OUT"
fi

cat <<EOF

${C_BOLD}分区对应关系（GPT，eMMC=/dev/mmcblk2 / SD=/dev/mmcblk0）：${C_OFF}
  uboot.img         -> 分区 1 (uboot)
  trust.img         -> 分区 2 (trust)
  MiniLoaderAll.bin -> 线刷/打包 sd-fuse 固件时使用

安装方式：
  ./rk3528-sdk.sh install-board      # 目标板 dd 更新
  ./rk3528-sdk.sh flash-loader       # 主机 upgrade_tool 线刷

EOF
