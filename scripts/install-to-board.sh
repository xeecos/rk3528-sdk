#!/usr/bin/env bash
# 在【目标板】上用 dd 更新 GPT 分区（resource / kernel / uboot / trust）
# 对应 WiKi「应用新编译的uboot与内核 / 安装到目标板」
#
# ⚠️ 高危：写错设备会直接破坏系统。默认只打印计划，必须加 --execute 才会真正写入。
#
# 用法（在开发板上、以 root 执行）：
#   sudo ./rk3528-sdk.sh install-board --device /dev/mmcblk2 \
#        --kernel /path/kernel.img --resource /path/resource.img --execute
#   --uboot FILE --trust FILE   可选，更新 uboot / trust 分区
#   --img-dir DIR              从目录自动寻找 kernel.img/resource.img/uboot.img/trust.img
#   --no-backup                跳过写入前的分区备份（默认备份）
# ==============================================================================
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/config.sh"

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; }

DEVICE=""
EXECUTE=0
BACKUP=1
IMG_DIR=""
declare -A IMGS=()
while (($#)); do
    case "$1" in
        --device) shift; DEVICE="${1:?--device 缺少参数}" ;;
        --device=*) DEVICE="${1#*=}" ;;
        --kernel|--resource|--uboot|--trust)
            key="${1#--}"; shift; [[ $# -gt 0 ]] || die "$key 缺少参数"; IMGS[$key]="$1" ;;
        --img-dir) shift; IMG_DIR="${1:?--img-dir 缺少参数}" ;;
        --execute) EXECUTE=1 ;;
        --no-backup) BACKUP=0 ;;
        --yes) export RK_ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "未知参数: $1（运行 install-board --help）" ;;
    esac
    shift
done

require_linux

# 自动从产物目录寻找镜像
if [[ -n "$IMG_DIR" ]]; then
    require_dir "$IMG_DIR"
    for k in kernel resource uboot trust; do
        [[ -n "${IMGS[$k]:-}" ]] && continue
        [[ -f "$IMG_DIR/$k.img" ]] && IMGS[$k]="$IMG_DIR/$k.img"
    done
fi
# 默认产物目录兜底
for k in kernel resource; do
    if [[ -z "${IMGS[$k]:-}" && -f "$RK_KERNEL_IMG_OUT/$k.img" ]]; then
        IMGS[$k]="$RK_KERNEL_IMG_OUT/$k.img"
    fi
done
for k in uboot trust; do
    if [[ -z "${IMGS[$k]:-}" && -f "$RK_UBOOT_IMG_OUT/$k.img" ]]; then
        IMGS[$k]="$RK_UBOOT_IMG_OUT/$k.img"
    fi
done

((${#IMGS[@]} > 0)) || die "没有指定任何镜像；请用 --kernel/--resource/--uboot/--trust 或 --img-dir 指定"
[[ -n "$DEVICE" ]] || die "必须用 --device 指定目标块设备（eMMC=/dev/mmcblk2, SD=/dev/mmcblk0）"

# WiKi 给出的 RK3528 默认 GPT 布局（在 lsblk 读不到 PARTLABEL 时回退）
declare -A FALLBACK_NO=([uboot]=1 [trust]=2 [resource]=5 [kernel]=6)

log_step "分区更新计划"
log_info "目标设备: $DEVICE"
log_info "运行模式: $( ((EXECUTE)) && echo '实际写入 (--execute)' || echo '仅预演（加 --execute 才会写入）' )"
log_info "架构    : $(uname -m)（本脚本应在 ARM 开发板上执行）"
# 注意：这里检查的是【目标板】（RK3528 是 arm64），不是构建主机平台。
# 本脚本在设计上就运行于开发板，与「只支持 Ubuntu x86_64 / WSL2 构建主机」的口径不冲突。
if [[ "$(uname -m)" != "aarch64" && "$(uname -m)" != "armv"* ]]; then
    log_warn "当前不是 ARM 架构，请确认你不是在 x86 主机上误操作"
fi

if [[ "${RK_DRY_RUN:-0}" != "1" && -b "$DEVICE" ]]; then
    log_step "当前分区布局"
    if have_cmd parted; then
        parted "$DEVICE" print 2>/dev/null || true
    else
        lsblk -o NAME,SIZE,PARTLABEL "$DEVICE"
    fi
fi

# 按 GPT 分区名定位，失败则回退到默认编号
partition_of() {
    local key=$1 dev=$DEVICE part
    if have_cmd lsblk && [[ -b "$dev" ]]; then
        part=$(lsblk -rno NAME,PARTLABEL "$dev" 2>/dev/null \
               | awk -v l="$key" '$2==l {print "/dev/"$1; exit}')
        [[ -n "$part" ]] && { echo "$part"; return 0; }
    fi
    local n=${FALLBACK_NO[$key]:-}
    [[ -z "$n" ]] && return 1
    if have_cmd lsblk && [[ -b "$dev" ]]; then
        part=$(lsblk -rno NAME "$dev" 2>/dev/null | sed -n "$((n + 1))p")
        [[ -n "$part" ]] && { echo "/dev/$part"; return 0; }
    fi
    # 最后回退：mmcblkXpN
    echo "${dev}p${n}"
}

declare -A TARGETS=()
for k in "${!IMGS[@]}"; do
    f="${IMGS[$k]}"
    require_file "$f"
    t=$(partition_of "$k")
    TARGETS[$k]="$t"
    sz=$(stat -c %s "$f" 2>/dev/null || echo 0)
    printf '  %-9s %-58s -> %-20s (%s bytes)\n' "$k" "$f" "$t" "$sz"
done

if [[ "${RK_DRY_RUN:-0}" != "1" ]]; then
    for k in "${!TARGETS[@]}"; do
        t="${TARGETS[$k]}"
        [[ -b "$t" ]] || die "分区 $t 不存在，请先用 parted $DEVICE print 核对分区布局"
        f="${IMGS[$k]}"
        sz=$(stat -c %s "$f")
        if have_cmd blockdev; then
            cap=$(blockdev --getsize64 "$t" 2>/dev/null || echo 0)
        else
            cap=$(lsblk -bno SIZE -d "$t" 2>/dev/null | head -1 || echo 0)
        fi
        if [[ "$cap" =~ ^[0-9]+$ ]] && (( cap > 0 && sz > cap )); then
            die "$f ($sz B) 超过分区 $t 容量 ($cap B)，拒绝写入"
        fi
        log_ok "容量检查通过: $k -> $t (分区 $((cap / 1024 / 1024)) MiB)"
    done
fi

if (( ! EXECUTE )); then
    echo
    log_warn "当前为预演模式，未写入任何数据。"
    log_info "确认无误后追加 --execute 重新执行（默认会先备份原分区）"
    exit 0
fi

if [[ "${RK_DRY_RUN:-0}" != "1" ]]; then
    require_root
    need_cmds dd sync
fi

plan=""
for k in "${!TARGETS[@]}"; do
    plan+="  dd if=${IMGS[$k]} of=${TARGETS[$k]} bs=1M"$'\n'
done
echo
log_warn "即将执行以下写入："
printf '%s' "$plan"
BACKUP_DIR="${RK_OUTPUT_DIR}/partition-backup-$(date +%Y%m%d-%H%M%S)"
if (( BACKUP )); then
    log_info "写入前将备份到: $BACKUP_DIR"
fi

if [[ "${RK_DRY_RUN:-0}" != "1" ]]; then
    confirm_dangerous "$DEVICE" \
        "上述 dd 会覆盖 ${DEVICE} 的对应分区，操作不可撤销！
  若 kernel/resource 不匹配，开发板可能无法启动（可用线刷恢复）。
  目标设备: $DEVICE"
else
    log_warn "[预演] 跳过危险确认与 root 检查"
fi

if (( BACKUP )); then
    log_step "备份原分区"
    ensure_dir "$BACKUP_DIR"
    for k in "${!TARGETS[@]}"; do
        run dd if="${TARGETS[$k]}" of="${BACKUP_DIR}/${k}.img" bs=1M status=none
    done
    log_ok "备份完成: $BACKUP_DIR"
fi

log_step "写入分区"
for k in "${!TARGETS[@]}"; do
    log_info "$k: ${IMGS[$k]} -> ${TARGETS[$k]}"
    run dd if="${IMGS[$k]}" of="${TARGETS[$k]}" bs=1M status=progress
done
run sync
log_ok "写入完成，请重启开发板验证：sudo reboot"
log_info "若还需更新内核模块，把 kernel-modules-*.tar.gz 解压后替换开发板 /lib/modules 目录"
