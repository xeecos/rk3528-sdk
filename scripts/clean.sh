#!/usr/bin/env bash
# 清理本工具生成的产物（不触碰 workspace/ 下的源码）
# 用法: clean.sh [images|logs|all] [--yes]
# ==============================================================================
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/config.sh"

require_linux   # 与其它脚本一致，统一遵守支持矩阵（WSL1 / 非 Linux 直接拒绝）

WHAT="images"
for arg in "$@"; do
    case "$arg" in
        --yes|-y) export RK_ASSUME_YES=1 ;;
        --dry-run) : ;;
        -*) : ;;
        *) if [[ "$WHAT" == "images" ]]; then WHAT="$arg"; fi ;;
    esac
done

case "$WHAT" in
    images|logs|all|-h|--help|help) : ;;
    *) die "未知目标: $WHAT（可用 images / logs / all）" ;;
esac
if [[ "$WHAT" == "-h" || "$WHAT" == "--help" || "$WHAT" == "help" ]]; then
    echo "用法: ./rk3528-sdk.sh clean [images|logs|all] [--yes]"
    echo "  images  清理 out/ 下本工具生成的镜像、模块包、分区备份"
    echo "  logs    清理 logs/ 下的构建日志"
    echo "  all     以上两者"
    echo "注意：workspace/ 下的源码与 sd-fuse/out 不受影响"
    exit 0
fi

# 精确列出待删文件（不做递归目录删除）
FILES=()
if [[ "$WHAT" == "images" || "$WHAT" == "all" ]]; then
    while IFS= read -r -d '' f; do FILES+=("$f"); done < <(
        find "$RK_OUTPUT_DIR" -maxdepth 2 -type f \
            \( -name '*.img' -o -name '*.img.gz' -o -name '*.tgz' \
               -o -name '*.tar.gz' -o -name '*.deb' -o -name '*.zip' -o -name '*.7z' \) \
            -print0 2>/dev/null)
    # 分区备份目录里的文件
    while IFS= read -r -d '' f; do FILES+=("$f"); done < <(
        find "$RK_OUTPUT_DIR" -maxdepth 2 -path '*/partition-backup-*/*.img' -type f -print0 2>/dev/null)
fi
if [[ "$WHAT" == "logs" || "$WHAT" == "all" ]]; then
    while IFS= read -r -d '' f; do FILES+=("$f"); done < <(
        find "$RK_LOG_DIR" -maxdepth 1 -type f -name '*.log' -print0 2>/dev/null)
fi

if ((${#FILES[@]} == 0)); then
    log_ok "没有需要清理的文件"
    exit 0
fi

log_step "待清理文件（共 ${#FILES[@]} 个）"
printf '  %s\n' "${FILES[@]}"
echo
log_warn "仅删除上述文件；workspace/ 源码与 sd-fuse/out 不受影响"
if ! confirm "确认删除这些文件?"; then
    die "已取消"
fi

if [[ "${RK_DRY_RUN:-0}" == "1" ]]; then
    printf '%s[DRY-RUN]%s rm -f (%d 个文件)\n' "${C_YELLOW}" "${C_OFF}" "${#FILES[@]}"
    exit 0
fi
rm -f -- "${FILES[@]}"
log_ok "已清理 ${#FILES[@]} 个文件"

# 清掉空的备份目录（仅限本工具创建的目录名）
find "$RK_OUTPUT_DIR" -maxdepth 1 -type d -name 'partition-backup-*' -empty -delete 2>/dev/null || true
