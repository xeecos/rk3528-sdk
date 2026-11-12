#!/usr/bin/env bash
# FriendlyWrt 25.12 编译 —— 对应 WiKi「编译 Openwrt/Friendlywrt」整章
# 用法: fw-build.sh <target> [选项]
#   target: all docker uboot kernel friendlywrt sd-img emmc-img
#           menuconfig rebuild single clean cleanall
# ==============================================================================
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/config.sh"

usage() {
    cat <<EOF
用法: ./rk3528-sdk.sh fw-build <target> [选项]

目标：
  all          首次全量编译 ./build.sh ${RK_FW_BOARD_MK}（u-boot+kernel+friendlywrt+sd-img）
  docker       全量编译 docker 版本 ./build.sh ${RK_FW_BOARD_MK_DOCKER}
  uboot        单独编译 u-boot          ./build.sh uboot
  kernel       单独编译 kernel          ./build.sh kernel
  friendlywrt  单独编译 rootfs          ./build.sh friendlywrt
  sd-img       重新打包 SD 卡镜像       ./build.sh sd-img
  emmc-img     打包 eMMC(eflasher) 镜像  ./build.sh emmc-img
  menuconfig   在 friendlywrt/ 中修改配置
  rebuild      二次编译：rm -rf tmp -> make -> sd-img -> emmc-img
  single       单线程排错编译 make -j1 V=s（--docker 时先清 go 缓存）
  clean        清理 out/ 下的旧镜像
  cleanall     彻底清理（u-boot/kernel distclean + friendlywrt clean）

选项：
  --docker     仅用于 single：按 docker 版本清 tmp/go-build
  --no-log     不写构建日志文件
  --yes        跳过交互确认
EOF
}

(($#)) || { usage; exit 1; }
TARGET=$1; shift
DOCKER=0
DO_LOG=1
while (($#)); do
    case "$1" in
        --docker) DOCKER=1 ;;
        --no-log) DO_LOG=0 ;;
        --yes) export RK_ASSUME_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "未知参数: $1（运行 fw-build --help 查看用法）" ;;
    esac
    shift
done

require_linux
require_not_root

FW="$RK_FW_DIR"
BUILD="$FW/build.sh"
require_dir "$FW" "（请先执行 ./rk3528-sdk.sh fw-init）"
require_file "$BUILD" "（源码不完整，请重跑 fw-init）"
if [[ ! "$TARGET" =~ ^(all|docker|uboot|u-boot|kernel|friendlywrt|sd-img|emmc-img|menuconfig|rebuild|single|clean|cleanall)$ ]]; then
    log_error "未知目标: $TARGET"
    usage
    exit 1
fi

# 除板级配置(all/docker) 外，都需要先选过板（存在 .current_config.mk）
need_config() {
    if [[ ! -e "$FW/.current_config.mk" ]]; then
        if [[ "${RK_DRY_RUN:-0}" == "1" ]]; then
            log_warn "[预演] 尚未选择板型配置（缺少 .current_config.mk），实际执行前需先跑 fw-build all"
            return 0
        fi
        die "尚未选择板型配置（缺少 .current_config.mk）。请先执行一次：
  ./rk3528-sdk.sh fw-build all        # 或 fw-build docker"
    fi
    log_info "当前板型配置: $(readlink "$FW/.current_config.mk" 2>/dev/null || echo '?')"
}

LOGFILE="${RK_LOG_DIR}/fw-build-${TARGET}-$(date +%Y%m%d-%H%M%S).log"
build() {
    if (( DO_LOG )) && [[ "$TARGET" != "menuconfig" ]]; then
        run_in_logged "$FW" "$LOGFILE" ./build.sh "$1"
    else
        run_in "$FW" ./build.sh "$1"
    fi
}

log_step "编译环境"
log_info "工程目录: $FW"
log_info "并行线程: $(jobs_count)"
log_info "日志文件: $( ((DO_LOG)) && echo "$LOGFILE" || echo '（关闭）' )"
check_free_gb "$RK_WORKSPACE" "$RK_MIN_FREE_GB" || \
    log_warn "空间偏低，全量编译可能中途失败"

case "$TARGET" in
    all|docker)
        if [[ "$TARGET" == "docker" ]]; then
            MK="$RK_FW_BOARD_MK_DOCKER"
        else
            MK="$RK_FW_BOARD_MK"
        fi
        log_step "全量编译：$MK"
        if [[ -d "$FW/device/friendlyelec" ]] && \
           [[ -z "$(find "$FW/device/friendlyelec" -name "$MK" -print -quit 2>/dev/null)" ]]; then
            log_warn "device/friendlyelec 下未找到 $MK，请确认 manifest 分支是否正确"
        fi
        log_info "该步骤包含 u-boot、kernel、friendlywrt 与 SD 镜像，耗时可能 1~3 小时"
        build "$MK"
        log_ok "全量编译完成，SD 镜像位于 $FW/out"
        log_info "如需 eMMC 卡刷固件，继续执行: ./rk3528-sdk.sh fw-build emmc-img"
        ;;

    uboot|u-boot|kernel|friendlywrt|sd-img|emmc-img|clean|cleanall)
        need_config
        log_step "执行 ./build.sh $TARGET"
        build "$TARGET"
        log_ok "$TARGET 完成"
        ;;

    menuconfig)
        need_config
        log_step "make menuconfig（交互界面）"
        run_in "$FW/friendlywrt" make menuconfig
        log_info "改完配置后建议执行: ./rk3528-sdk.sh fw-build rebuild"
        ;;

    rebuild)
        need_config
        log_step "二次编译"
        # WiKi 流程：rm -rf ./tmp 后重新 make，确保 menuconfig 的改动完整生效
        TMP_DIR="$FW/friendlywrt/tmp"
        if [[ -d "$TMP_DIR" ]]; then
            log_warn "按 WiKi 流程将删除构建临时目录: $TMP_DIR"
            log_warn "OpenWrt 会在下次 make 时自动重建；如只想快速增量编译，请在提示时选 N"
            if confirm "确认删除 $TMP_DIR ?"; then
                run rm -rf -- "$TMP_DIR"
            else
                log_warn "跳过清理，改为直接增量编译"
            fi
        fi
        # WiKi 原文为 make -j${nproc}，此处改用真实线程数
        run_in_logged "$FW/friendlywrt" \
            "${RK_LOG_DIR}/fw-rebuild-$(date +%Y%m%d-%H%M%S).log" \
            make -j"$(jobs_count)"
        log_step "重新打包镜像"
        build sd-img
        build emmc-img
        log_ok "二次编译完成"
        ;;

    single)
        log_step "单线程排错编译"
        if (( DOCKER )); then
            log_info "docker 版：先清除 tmp/go-build 缓存"
            run_in "$FW/friendlywrt" rm -rf tmp/go-build
        fi
        run_in_logged "$FW/friendlywrt" \
            "${RK_LOG_DIR}/fw-single-$(date +%Y%m%d-%H%M%S).log" \
            make -j1 V=s
        log_ok "单线程编译完成"
        ;;
esac

if (( DO_LOG )) && [[ -f "$LOGFILE" ]]; then
    log_info "构建日志: $LOGFILE"
fi
