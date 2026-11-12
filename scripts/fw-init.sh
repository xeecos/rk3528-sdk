#!/usr/bin/env bash
# 下载 FriendlyWrt 25.12 (RK3528) 源码 —— 对应 WiKi「下载FriendlyWrt 25.12源代码」
# 用法: fw-init.sh [--force] [--branch B] [--manifest M] [--jobs N] [--yes]
# ==============================================================================
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/config.sh"

FORCE=0
BRANCH="$RK_FW_MANIFEST_BRANCH"
MANIFEST="$RK_FW_MANIFEST_FILE"
JOBS="$RK_REPO_JOBS"
while (($#)); do
    case "$1" in
        --force) FORCE=1 ;;
        --branch) shift; BRANCH="${1:?--branch 缺少参数}" ;;
        --manifest) shift; MANIFEST="${1:?--manifest 缺少参数}" ;;
        --jobs) shift; JOBS="${1:?--jobs 缺少参数}" ;;
        --yes) export RK_ASSUME_YES=1 ;;
        -h|--help)
            echo "用法: fw-init.sh [--force] [--branch B] [--manifest M] [--jobs N]"
            echo "  --force    即使 .repo 已存在也重新执行 repo init（不删除已有源码）"
            exit 0 ;;
        *) die "未知参数: $1" ;;
    esac
    shift
done

require_linux
require_not_root
need_cmds git python3
check_free_gb "$RK_WORKSPACE" "$RK_MIN_FREE_GB" || \
    die "磁盘空间不足，请设置 RK_MIN_FREE_GB 或把 RK_WORKSPACE 指向更大的磁盘"

log_step "目标目录"
log_info "$RK_FW_DIR"
log_info "manifest: $RK_FW_MANIFEST_URL  branch: $BRANCH  file: $MANIFEST"
ensure_dir "$RK_FW_DIR"

if ! git config --get user.email >/dev/null 2>&1 || ! git config --get user.name >/dev/null 2>&1; then
    log_warn "git 未配置 user.name / user.email，repo 可能提示；建议执行："
    log_warn "  git config --global user.name \"Your Name\" && git config --global user.email you@example.com"
fi

# repo 引导工具
log_step "下载 repo 引导工具"
git_clone "$RK_REPO_TOOL_URL" "${RK_FW_DIR}/tools" "" 1
REPO="${RK_FW_DIR}/tools/repo"
require_file "$REPO" "（repo 引导工具下载失败）"
if [[ "${RK_DRY_RUN:-0}" != "1" ]]; then
    chmod +x "$REPO"
fi

# repo init
if [[ -d "${RK_FW_DIR}/.repo" && "$FORCE" -eq 0 ]]; then
    log_ok "已初始化，跳过 repo init（如需切换 manifest 请加 --force）"
else
    log_step "repo init"
    run_in "$RK_FW_DIR" "$REPO" init \
        -u "$RK_FW_MANIFEST_URL" -b "$BRANCH" \
        -m "$MANIFEST" --repo-url="$RK_REPO_TOOL_URL" --no-clone-bundle
fi

# repo sync（支持中断后续传）
log_step "repo sync (并发 ${JOBS})"
run_in "$RK_FW_DIR" "$REPO" sync -c --no-clone-bundle -j"$JOBS" || {
        log_warn "sync 中断，可直接重跑本命令续传（repo sync 支持断点续传）"
        exit 1
    }

log_step "源码工程组成"
for p in kernel u-boot rkbin scripts/sd-fuse device/common device/friendlyelec configs friendlywrt toolchain; do
    if [[ -d "${RK_FW_DIR}/${p}" ]]; then
        printf '  %s[OK]%s    %s\n' "$C_GREEN" "$C_OFF" "$p"
    else
        printf '  %s[缺失]%s %s\n' "$C_YELLOW" "$C_OFF" "$p"
    fi
done

cat <<EOF

${C_BOLD}下一步：${C_OFF}
  ./rk3528-sdk.sh fw-build all          # 全量编译（生成 SD 镜像）
  ./rk3528-sdk.sh fw-build docker       # docker 版本
  ./rk3528-sdk.sh fw-build emmc-img     # 首次编译后另生成 eMMC 卡刷固件

EOF
