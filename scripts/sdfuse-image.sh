#!/usr/bin/env bash
# 生成 SD 固件 / SD-to-eMMC 卡刷固件，或直接烧写 SD 卡
# 对应 sd-fuse 官方 README 的 mk-sd-image.sh / mk-emmc-image.sh / fusing.sh
#
# 用法: sdfuse-image.sh <sd|emmc|fuse> [OS] [选项]
#   --device /dev/sdX   fuse 模式必填，目标 SD 卡设备
#   --raw-size-mb N     设置 RAW_SIZE_MB（镜像过大时使用）
#   --no-overlayfs      用 parameter-plain.txt + dtbo-plain.img 禁用 OverlayFS
#   --no-collect        不把 out/ 下产物复制到 RK_OUTPUT_DIR
# ==============================================================================
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/config.sh"

usage() {
    cat <<EOF
用法: ./rk3528-sdk.sh sdfuse-image <sd|emmc|fuse> [OS] [选项]
  sd     生成 SD 卡启动镜像     -> out/rk3528-sd-<OS>-6.1-arm64-YYYYMMDD.img
  emmc   生成 SD-to-eMMC 卡刷镜像 -> out/rk3528-eflasher-<OS>-6.1-arm64-YYYYMMDD.img
         需要 eflasher 分区镜像（sdfuse-init --with-eflasher）
  fuse   直接写入 SD 卡（sudo ./fusing.sh /dev/sdX <OS>），高危
OS 省略时使用 ${RK_DEFAULT_OS}。
EOF
}

(($#)) || { usage; exit 1; }
ACTION=$1; shift
OS=""
DEVICE=""
RAW_SIZE=""
NO_OVERLAYFS=0
COLLECT=1
while (($#)); do
    case "$1" in
        --device) shift; DEVICE="${1:?--device 缺少参数}" ;;
        --device=*) DEVICE="${1#*=}" ;;
        --raw-size-mb) shift; RAW_SIZE="${1:?--raw-size-mb 缺少参数}" ;;
        --no-overlayfs) NO_OVERLAYFS=1 ;;
        --no-collect) COLLECT=0 ;;
        --yes) export RK_ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        -*) die "未知参数: $1" ;;
        *) [[ -z "$OS" ]] || die "多余的 OS 参数: $1"; OS="$1" ;;
    esac
    shift
done
OS="${OS:-$RK_DEFAULT_OS}"
validate_os "$OS"
[[ "$ACTION" =~ ^(sd|emmc|fuse)$ ]] || die "未知动作: $ACTION（可用 sd / emmc / fuse）"

require_linux
require_not_root

DIR="$RK_SDFUSE_DIR"
require_dir "$DIR" "（请先执行 ./rk3528-sdk.sh sdfuse-init）"
require_dir "$DIR/$OS" "（缺少分区镜像目录）"
require_file "$DIR/mk-sd-image.sh" "（sd-fuse 源码不完整）"

ENVV=(env "SDFUSE_NONINTERACTIVE=${SDFUSE_NONINTERACTIVE:-y}")
[[ -n "$RAW_SIZE" ]] && ENVV+=("RAW_SIZE_MB=$RAW_SIZE")

log_step "sd-fuse 打包：$ACTION / $OS"
log_info "脚本目录: $DIR"
[[ -n "$RAW_SIZE" ]] && log_info "RAW_SIZE_MB=$RAW_SIZE"

if (( NO_OVERLAYFS )); then
    log_step "禁用 OverlayFS"
    require_file "$DIR/prebuilt/parameter-plain.txt"
    require_file "$DIR/prebuilt/dtbo-plain.img"
    run cp -f "$DIR/prebuilt/parameter-plain.txt" "$DIR/$OS/parameter.txt"
    run cp -f "$DIR/prebuilt/dtbo-plain.img" "$DIR/$OS/dtbo.img"
    log_ok "已替换 parameter.txt / dtbo.img（禁用 OverlayFS，便于 Docker/Swap）"
fi

LOGFILE="${RK_LOG_DIR}/sdfuse-image-${ACTION}-${OS}-$(date +%Y%m%d-%H%M%S).log"

case "$ACTION" in
    sd)
        run_in_logged "$DIR" "$LOGFILE" "${ENVV[@]}" ./mk-sd-image.sh "$OS"
        ;;
    emmc)
        require_dir "$DIR/eflasher" "（缺少 eflasher 分区镜像，请执行 sdfuse-init $OS --with-eflasher）"
        require_file "$DIR/mk-emmc-image.sh"
        run_in_logged "$DIR" "$LOGFILE" "${ENVV[@]}" ./mk-emmc-image.sh "$OS" autostart=yes
        ;;
    fuse)
        [[ -n "$DEVICE" ]] || die "fuse 模式必须用 --device 指定 SD 卡设备，例如 --device /dev/sdX"
        require_file "$DIR/fusing.sh"
        if [[ "${RK_DRY_RUN:-0}" != "1" ]]; then
            [[ -b "$DEVICE" ]] || die "$DEVICE 不是块设备，请确认设备名"
            log_step "确认目标设备"
            show_block_devices
            confirm_dangerous "$DEVICE" \
                "即将把 $OS 系统写入 ${DEVICE}，该设备上所有数据将被永久抹除！
  请再次核对设备名，误写到系统盘会导致主机数据丢失。
  目标: $DEVICE    OS: $OS"
        else
            log_warn "[预演] 跳过设备存在性检查与危险确认"
        fi
        run_in "$DIR" sudo env "${ENVV[@]:1}" ./fusing.sh "$DEVICE" "$OS"
        log_ok "烧写完成：$DEVICE"
        exit 0
        ;;
esac

# 收集产物
if (( COLLECT )) && [[ "${RK_DRY_RUN:-0}" != "1" ]]; then
    log_step "收集产物"
    ensure_dir "$RK_OUTPUT_DIR"
    found=0
    while IFS= read -r -d '' f; do
        cp -f "$f" "$RK_OUTPUT_DIR/"
        log_ok "$(basename "$f")  ($(du -h "$f" | awk '{print $1}'))"
        found=$((found + 1))
    done < <(find "$DIR/out" -maxdepth 1 -type f \( -name '*.img' -o -name '*.img.gz' -o -name '*.7z' -o -name '*.zip' \) -print0 2>/dev/null)
    (( found > 0 )) || log_warn "未在 $DIR/out 找到新生成的镜像，请查看日志: $LOGFILE"
    log_info "产物已复制到 $RK_OUTPUT_DIR"
fi

cat <<EOF

${C_BOLD}烧写方式：${C_OFF}
  sudo dd if=${RK_OUTPUT_DIR}/<镜像名>.img of=/dev/sdX bs=1M status=progress
  或  ./rk3528-sdk.sh sdfuse-image fuse $OS --device /dev/sdX
  Windows 下可用 RKDevTool / balenaEtcher / Win32DiskImager

EOF
