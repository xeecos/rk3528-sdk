#!/usr/bin/env bash
# 用 Rockchip Linux_Upgrade_Tool (v2+) 线刷 uboot / kernel / resource
# 对应 WiKi「应用新编译的uboot与内核 / 线刷 / Linux系统」
#
# ⚠️ 默认只打印计划，必须加 --execute 才真正烧写。
# 前置：开发板已进入 loader 模式（在开发板系统内执行 `sudo reboot loader`，
#       或按住 Maskrom/Recovery 键上电），并用 USB 线连接到主机。
#
# 用法: sudo ./rk3528-sdk.sh flash-loader --kernel FILE --resource FILE [--uboot FILE] --execute
#   --img-dir DIR     从目录寻找 kernel.img/resource.img/uboot.img
#   --tool PATH       指定 upgrade_tool 路径（默认自动查找）
#   --no-reboot       烧写后不执行 upgrade_tool RD
# ==============================================================================
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/config.sh"

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }

EXECUTE=0
REBOOT=1
IMG_DIR=""
TOOL=""
declare -A IMGS=()
while (($#)); do
    case "$1" in
        --kernel|--resource|--uboot)
            key="${1#--}"; shift; [[ $# -gt 0 ]] || die "$key 缺少参数"; IMGS[$key]="$1" ;;
        --img-dir) shift; IMG_DIR="${1:?--img-dir 缺少参数}" ;;
        --tool) shift; TOOL="${1:?--tool 缺少参数}" ;;
        --execute) EXECUTE=1 ;;
        --no-reboot) REBOOT=0 ;;
        --yes) export RK_ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "未知参数: $1" ;;
    esac
    shift
done

require_linux

if [[ -n "$IMG_DIR" ]]; then
    require_dir "$IMG_DIR"
    for k in kernel resource uboot; do
        if [[ -z "${IMGS[$k]:-}" && -f "$IMG_DIR/$k.img" ]]; then
            IMGS[$k]="$IMG_DIR/$k.img"
        fi
    done
fi
for k in kernel resource; do
    if [[ -z "${IMGS[$k]:-}" && -f "$RK_KERNEL_IMG_OUT/$k.img" ]]; then
        IMGS[$k]="$RK_KERNEL_IMG_OUT/$k.img"
    fi
done
if [[ -z "${IMGS[uboot]:-}" && -f "$RK_UBOOT_IMG_OUT/uboot.img" ]]; then
    IMGS[uboot]="$RK_UBOOT_IMG_OUT/uboot.img"
fi

for k in kernel resource; do
    [[ -n "${IMGS[$k]:-}" ]] || die "缺少 $k.img，请用 --$k 或 --img-dir 指定"
done

# 定位 upgrade_tool
if [[ -z "$TOOL" ]]; then
    if have_cmd upgrade_tool; then
        TOOL=$(command -v upgrade_tool)
    elif [[ -x "${RK_DOWNLOAD_DIR}/tools/upgrade_tool" ]]; then
        TOOL="${RK_DOWNLOAD_DIR}/tools/upgrade_tool"
    else
        TOOL="upgrade_tool"
        log_warn "未找到 upgrade_tool；请安装 Linux_Upgrade_Tool v2.x（例如 v2.30）后用 --tool 指定"
    fi
fi

log_step "线刷计划"
log_info "工具: $TOOL"
log_info "模式: $( ((EXECUTE)) && echo '实际烧写 (--execute)' || echo '仅预演' )"
for k in "${!IMGS[@]}"; do
    printf '  %-9s %s\n' "$k" "${IMGS[$k]}"
    require_file "${IMGS[$k]}"
done

cat <<'EOF'

前置检查清单（在主机执行本脚本前确认）：
  1) 开发板已执行 `sudo reboot loader` 进入 loader 模式
  2) USB Type-C / USB OTG 线已连接开发板与主机
  3) 主机执行 `upgrade_tool LD` 能看到一个 Loader/Maskrom 设备
  4) 使用的 Linux_Upgrade_Tool 版本 >= v2（v1 不支持这些 di 参数）

EOF

if [[ "${RK_DRY_RUN:-0}" != "1" ]]; then
    if ! have_cmd "$TOOL" && [[ ! -x "$TOOL" ]]; then
        die "upgrade_tool 不可用: $TOOL。请下载 Linux_Upgrade_Tool_v2.30_for_linux 并用 --tool 指定可执行文件"
    fi
    log_step "检测设备"
    "$TOOL" LD 2>&1 | head -20 || true
fi

# 生成命令清单
# 用 TAB 分隔「参数」与「文件路径」，避免路径含空格时被拆错
CMDS=()
if [[ -n "${IMGS[kernel]:-}" ]]; then   CMDS+=("di -k"$'\t'"${IMGS[kernel]}"); fi
if [[ -n "${IMGS[resource]:-}" ]]; then CMDS+=("di -re"$'\t'"${IMGS[resource]}"); fi
if [[ -n "${IMGS[uboot]:-}" ]]; then    CMDS+=("di -u"$'\t'"${IMGS[uboot]}"); fi
if (( REBOOT )); then                   CMDS+=("RD"); fi

echo
log_warn "即将执行："
for c in "${CMDS[@]}"; do printf '  sudo %s %s\n' "$TOOL" "${c//$'\t'/ }"; done

if (( ! EXECUTE )); then
    echo
    log_warn "当前为预演模式，未烧写。确认后追加 --execute 重新执行"
    exit 0
fi

if [[ "${RK_DRY_RUN:-0}" != "1" ]]; then
    confirm_dangerous "LOADER" \
        "线刷会覆盖开发板上的 uboot / kernel / resource，出错可能导致无法启动。
  请确认设备已进入 loader 模式且只有一块板子连接到主机。"
else
    log_warn "[预演] 跳过危险确认"
fi

log_step "开始烧写"
for c in "${CMDS[@]}"; do
    IFS=$'\t' read -r flag path <<<"$c"
    if [[ -n "${path:-}" ]]; then
        read -r -a opts <<<"$flag"     # 例如 "di -k" -> ("di" "-k")
        run sudo "$TOOL" "${opts[@]}" "$path"
    else
        run sudo "$TOOL" "$flag"       # 例如 "RD"
    fi
done
log_ok "线刷完成，开发板应已重启"
