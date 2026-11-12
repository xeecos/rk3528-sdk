#!/usr/bin/env bash
# 初始化 sd-fuse_rk3528 工作区：克隆脚本 + 准备分区镜像文件
# 对应 WiKi「使用脚本进行编译 / 下载工具与固件」与 sd-fuse 官方 README
#
# 用法: sdfuse-init.sh [OS] [--images FILE|URL] [--with-eflasher] [--force] [--yes]
#   OS 省略时使用 RK_DEFAULT_OS (${RK_DEFAULT_OS})
#   --images 可传网盘里的 xxx-images.tgz 本地路径、或完整下载 URL
# ==============================================================================
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/config.sh"

OS=""
IMAGES=""
WITH_EFLASHER=0
FORCE=0
while (($#)); do
    case "$1" in
        --images) shift; IMAGES="${1:?--images 缺少参数}" ;;
        --images=*) IMAGES="${1#*=}" ;;
        --os) shift; OS="${1:?--os 缺少参数}" ;;
        --with-eflasher) WITH_EFLASHER=1 ;;
        --force) FORCE=1 ;;
        --yes) export RK_ASSUME_YES=1 ;;
        -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) die "未知参数: $1" ;;
        *) [[ -z "$OS" ]] || die "只能指定一个 OS，收到多余参数: $1"; OS="$1" ;;
    esac
    shift
done
OS="${OS:-$RK_DEFAULT_OS}"
validate_os "$OS"

require_linux
require_not_root
need_cmds git tar

DIR="$RK_SDFUSE_DIR"
log_step "初始化 sd-fuse 工作区"
log_info "脚本目录: $DIR (分支 $RK_SDFUSE_BRANCH)"
log_info "目标 OS : $OS"
check_free_gb "$RK_WORKSPACE" 15 || log_warn "空间偏低，分区镜像解压后通常占用 3~10 GB"

git_clone "$RK_SDFUSE_REPO" "$DIR" "$RK_SDFUSE_BRANCH" 1
require_dir "$DIR"

# ------------------------------------------------------------------------------
# 分区镜像包
# ------------------------------------------------------------------------------
prepare_images() {
    local src=$1 label=$2
    local pkg="$src"
    if [[ "$src" =~ ^https?:// ]]; then
        pkg="${RK_DOWNLOAD_DIR}/$(basename "${src%%\?*}")"
        download "$src" "$pkg"
    elif [[ ! -f "$src" ]]; then
        die "镜像包不存在: $src（可传本地路径、HTTP URL，或省略以从官方服务器下载）"
    fi
    log_info "$label 镜像包: $pkg"
    if [[ -d "$DIR/$OS" && "$FORCE" -eq 0 ]]; then
        log_ok "目录 $DIR/$OS 已存在，跳过解压（如需覆盖加 --force）"
        return 0
    fi
    log_step "解压 $label 分区镜像到 $DIR"
    run tar xvzf "$pkg" -C "$DIR"
}

if [[ -n "$IMAGES" ]]; then
    prepare_images "$IMAGES" "$OS"
elif [[ "${RK_DRY_RUN:-0}" == "1" ]]; then
    printf '%s[DRY-RUN]%s download %q -> %q && tar xvzf ... -C %q\n' \
        "${C_YELLOW}" "${C_OFF}" "${RK_IMAGES_BASE_URL}/${OS}-images.tgz" \
        "${RK_DOWNLOAD_DIR}/${OS}-images.tgz" "$DIR"
else
    if [[ -d "$DIR/$OS" && "$FORCE" -eq 0 ]]; then
        log_ok "目录 $DIR/$OS 已存在，跳过下载（如需覆盖加 --force）"
    else
        log_info "镜像包来源: ${RK_IMAGES_BASE_URL}/${OS}-images.tgz"
        log_info "若网络不通，可从网盘 03_分区镜像文件 下载后用 --images 指定"
        download "${RK_IMAGES_BASE_URL}/${OS}-images.tgz" \
                 "${RK_DOWNLOAD_DIR}/${OS}-images.tgz"
        run tar xvzf "${RK_DOWNLOAD_DIR}/${OS}-images.tgz" -C "$DIR"
    fi
fi

# ------------------------------------------------------------------------------
# eflasher 系统镜像（制作 SD-to-eMMC 卡刷固件时需要）
# ------------------------------------------------------------------------------
if (( WITH_EFLASHER )); then
    log_step "准备 eflasher 分区镜像"
    EPKG="${RK_DOWNLOAD_DIR}/emmc-flasher-images.tgz"
    download "${RK_IMAGES_BASE_URL}/emmc-flasher-images.tgz" "$EPKG"
    if [[ -d "$DIR/eflasher" && "$FORCE" -eq 0 ]]; then
        log_ok "eflasher 目录已存在，跳过解压"
    else
        run tar xvzf "$EPKG" -C "$DIR"
    fi
fi

log_step "工作区状态"
if [[ -d "$DIR/$OS" ]]; then
    log_ok "分区镜像目录: $DIR/$OS"
    ls -1 "$DIR/$OS" | head -20 | sed 's/^/    /'
else
    log_warn "分区镜像目录尚未生成（预演模式属正常）"
fi

cat <<EOF

${C_BOLD}下一步：${C_OFF}
  ./rk3528-sdk.sh sdfuse-build kernel $OS     # 编译并更新内核
  ./rk3528-sdk.sh sdfuse-build headers $OS    # 仅编译内核头文件 deb
  ./rk3528-sdk.sh sdfuse-build uboot  $OS     # 编译并更新 u-boot
  ./rk3528-sdk.sh sdfuse-image sd     $OS     # 生成 SD 固件
  ./rk3528-sdk.sh sdfuse-image emmc   $OS     # 生成 SD-to-eMMC 卡刷固件（需 --with-eflasher）

常用环境变量（见 docs/04-sd-fuse打包.md）：
  RAW_SIZE_MB=16000   加大固件容量
  FS_TYPE=btrfs        使用 btrfs 根文件系统
  SDFUSE_NONINTERACTIVE=y（本工具默认已设置）

EOF
