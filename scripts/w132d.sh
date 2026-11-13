#!/usr/bin/env bash
# ==============================================================================
# 路线 D：ZTE Cloud Computer W132D 主线 Linux（独立上游仓库）
#
# 上游：https://github.com/zte-cloud-computer/w132d-linux-mainline
#   Linux 稳定内核 + 主线 U-Boot + Armbian 构建框架 + Debian trixie minimal
#
# ⚠️ 与路线 A/B/C（FriendlyELEC BSP）完全隔离：不共用内核源码、u-boot、
#    rkbin、sd-fuse、分区镜像或 11.3-aarch64 工具链。两套固件不可混刷。
#    本脚本只做「上游编排 + 环境检查 + 产物收集 + 安全刷写」，不重写上游构建系统。
#
# 用法：./rk3528-sdk.sh w132d <init|fetch|build|verify|flash|status|help> [参数]
# ==============================================================================
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/config.sh"

usage() {
    cat <<EOF
${C_BOLD}W132D 主线 Linux（独立路线 D）${C_OFF}
用法: ./rk3528-sdk.sh w132d <动作> [参数...]

${C_BOLD}动作${C_OFF}
  init                        克隆上游仓库并检查构建环境
  fetch [--latest] [--channel stable|experimental] [--detect] [--no-download]
                               锁定/下载上游来源，生成 out/manifest.json
  build [kernel|image|uboot|bsp|flash-tools|fnos]
                               构建目标（默认 kernel；完整镜像用 image）
  verify <static|tests|patches|debs|image|candidate>
                               运行与 CI 一致的检查
  flash [--tag TAG] [--execute|--verify-only]
                               下载 Release 刷写包、校验、预演；--execute 才真刷
  status                      查看上游、manifest、产物与刷写包状态
  help                        显示本帮助

${C_BOLD}示例${C_OFF}
  ./rk3528-sdk.sh w132d init
  ./rk3528-sdk.sh w132d fetch --download          # 等价于 fetch --download
  ./rk3528-sdk.sh w132d build image
  ./rk3528-sdk.sh w132d verify static
  ./rk3528-sdk.sh w132d flash                    # 只做校验与 dry-run
  ./rk3528-sdk.sh w132d flash --execute          # 真正刷写（高危）

${C_BOLD}重要边界${C_OFF}
  W132D 使用 Armbian GPT 整盘镜像（FAT boot + ext4 rootfs，主线 U-Boot），
  与 FriendlyELEC 的 Rockchip 参数分区固件不兼容，互刷会变砖。
  构建需要 Docker / Python ${RK_W132D_PYTHON_BUILD_MIN}+ / loop 设备 / >= ${RK_W132D_MIN_FREE_GB} GiB；
  刷写走 USB rkdeveloptool，WSL2 下 USB 直通与 Windows 路径均未获上游实机验证。
EOF
}

ACTION="${1:-help}"
if (($#)); then shift; fi
case "$ACTION" in
    help|-h|--help) usage; exit 0 ;;
esac

require_linux
require_not_root
need_cmds git python3

DIR="$RK_W132D_DIR"
TOOL="tools/w132d"

version_ge() {
    local have=$1 need=$2
    [[ "$(printf '%s\n%s\n' "$need" "$have" | sort -V | head -1)" == "$need" ]]
}
python_version() {
    python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo 0
}
manifest_version() {
    local m="$DIR/out/manifest.json"
    [[ -f "$m" ]] || return 1
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version","?"))' "$m" 2>/dev/null
}

# ------------------------------------------------------------------------------
# 环境检查（只报告，不硬拦；缺 Docker/loop 时由具体动作给出提示）
# ------------------------------------------------------------------------------
check_build_env() {
    log_step "W132D 构建环境"
    local pv
    pv="$(python_version)"
    if version_ge "$pv" "$RK_W132D_PYTHON_BUILD_MIN"; then
        log_ok "Python $pv (>= $RK_W132D_PYTHON_BUILD_MIN)"
    else
        log_warn "Python $pv 低于构建要求的 $RK_W132D_PYTHON_BUILD_MIN；刷写包只需 $RK_W132D_PYTHON_FLASH_MIN"
    fi
    if have_cmd docker; then
        log_ok "docker: $(command -v docker)"
    else
        log_warn "缺少 docker：Armbian 构建框架在容器中运行，build kernel/image/uboot/bsp 必需"
    fi
    for c in dtc sgdisk fdisk; do
        have_cmd "$c" && log_ok "$c 已安装" || log_warn "缺少 $c（完整镜像构建需要）"
    done
    if [[ -e /dev/loop-control ]]; then
        log_ok "loop 设备可用"
    else
        log_warn "未发现 /dev/loop-control：完整镜像构建需要 loop 设备"
    fi
    if ! check_free_gb "$DIR" "$RK_W132D_MIN_FREE_GB"; then
        log_warn "空闲空间低于上游要求的 ${RK_W132D_MIN_FREE_GB} GiB"
    fi
}

# ------------------------------------------------------------------------------
# init
# ------------------------------------------------------------------------------
do_init() {
    local ref="" check_only=0
    while (($#)); do
        case "$1" in
            --ref) shift; ref="${1:?--ref 缺少参数}" ;;
            --ref=*) ref="${1#*=}" ;;
            --check-only) check_only=1 ;;
            --yes) export RK_ASSUME_YES=1 ;;
            *) die "init: 未知参数: $1" ;;
        esac
        shift
    done

    if (( ! check_only )); then
        log_step "克隆 W132D 上游仓库"
        log_info "$RK_W132D_REPO  ($RK_W132D_BRANCH)"
        git_clone "$RK_W132D_REPO" "$DIR" "$RK_W132D_BRANCH" 1
        if [[ -n "$ref" && "${RK_DRY_RUN:-0}" != "1" ]]; then
            log_info "切换到指定引用: $ref"
            run_in "$DIR" git fetch --depth 1 origin "$ref"
            run_in "$DIR" git checkout --detach FETCH_HEAD
        fi
    fi
    require_dir "$DIR" "（请先执行 w132d init）"
    require_file "$DIR/$TOOL" "（上游仓库不完整）"
    log_ok "上游入口: $DIR/$TOOL"
    check_build_env
    cat <<EOF

${C_BOLD}下一步：${C_OFF}
  ./rk3528-sdk.sh w132d fetch --download     # 锁定并下载上游来源
  ./rk3528-sdk.sh w132d build image          # 构建完整 Armbian 镜像
  ./rk3528-sdk.sh w132d status               # 查看产物

EOF
}

# ------------------------------------------------------------------------------
# fetch
# ------------------------------------------------------------------------------
do_fetch() {
    local -a a=(fetch --download)
    while (($#)); do
        case "$1" in
            --latest) a+=(--latest) ;;
            --channel) shift; a+=(--channel "${1:?--channel 缺少参数}") ;;
            --detect) a+=(--detect) ;;
            --download) : ;;   # 默认即带 --download，显式给出也接受
            --no-download) a=(fetch) ;;
            --yes) export RK_ASSUME_YES=1 ;;
            *) die "fetch: 未知参数: $1" ;;
        esac
        shift
    done
    require_dir "$DIR" "（请先执行 w132d init）"
    require_file "$DIR/$TOOL" "（上游仓库不完整）"
    log_step "锁定并下载上游来源"
    log_info "命令: $TOOL ${a[*]}"
    run_in_logged "$DIR" "${RK_LOG_DIR}/w132d-fetch-$(date +%Y%m%d-%H%M%S).log" \
        "$TOOL" "${a[@]}"
    if [[ "${RK_DRY_RUN:-0}" != "1" ]]; then
        local v
        v="$(manifest_version || echo '?')"
        log_ok "manifest 版本: $v  ($DIR/out/manifest.json)"
        log_info "产物目录: $DIR/out/$v"
    fi
}

# ------------------------------------------------------------------------------
# build
# ------------------------------------------------------------------------------
do_build() {
    local target="kernel" framework="" output="" base_image="" base_sha=""
    if (($#)) && [[ "$1" != -* ]]; then target="$1"; shift; fi
    while (($#)); do
        case "$1" in
            --framework) shift; framework="${1:?--framework 缺少参数}" ;;
            --output) shift; output="${1:?--output 缺少参数}" ;;
            --base-image) shift; base_image="${1:?--base-image 缺少参数}" ;;
            --base-sha256) shift; base_sha="${1:?--base-sha256 缺少参数}" ;;
            --yes) export RK_ASSUME_YES=1 ;;
            *) die "build: 未知参数: $1" ;;
        esac
        shift
    done
    case "$target" in
        kernel|image|uboot|bsp|flash-tools|fnos) ;;
        *) die "未知构建目标: $target（可用 kernel/image/uboot/bsp/flash-tools/fnos）" ;;
    esac

    require_dir "$DIR" "（请先执行 w132d init）"
    require_file "$DIR/$TOOL" "（上游仓库不完整）"
    if [[ "$target" != "flash-tools" && "${RK_DRY_RUN:-0}" != "1" ]]; then
        require_file "$DIR/out/manifest.json" "（请先执行 w132d fetch --download）"
        if ! have_cmd docker; then
            die "build $target 需要 Docker（Armbian 构建框架）。请在受支持的 Ubuntu / WSL2 中安装并启动 docker；
  仅 w132d build flash-tools 不需要 Docker。"
        fi
    fi

    local -a a=(build "$target")
    [[ -n "$framework" ]] && a+=(--framework "$framework")
    [[ -n "$output" ]] && a+=(--output "$output")
    [[ -n "$base_image" ]] && a+=(--base-image "$base_image")
    [[ -n "$base_sha" ]] && a+=(--base-sha256 "$base_sha")
    if [[ "$target" == "fnos" && -z "$base_image" ]]; then
        log_warn "fnos 目标通常需要 --base-image 与 --base-sha256（见上游 docs/build.md）"
    fi

    log_step "构建 W132D: $target"
    log_info "命令: $TOOL ${a[*]}"
    log_info "耗时较长，日志同步写入 logs/"
    run_in_logged "$DIR" "${RK_LOG_DIR}/w132d-build-${target}-$(date +%Y%m%d-%H%M%S).log" \
        "$TOOL" "${a[@]}"

    if [[ "${RK_DRY_RUN:-0}" != "1" ]]; then
        local v
        v="$(manifest_version || echo '')"
        if [[ -n "$v" ]]; then
            log_ok "产物目录: $DIR/out/$v"
            [[ -f "$DIR/out/$v/w132d.img" ]] && log_ok "完整镜像: $DIR/out/$v/w132d.img"
            [[ -d "$DIR/out/$v/debs" ]] && log_info "软件包: $DIR/out/$v/debs"
        fi
        [[ -d "$DIR/out/flash-tools" ]] && log_info "刷写工具: $DIR/out/flash-tools"
    fi
}

# ------------------------------------------------------------------------------
# verify
# ------------------------------------------------------------------------------
do_verify() {
    local target="${1:-}"; (($#)) && shift
    local jobs=4 directory="" image="" full=0 use_docker=0
    while (($#)); do
        case "$1" in
            --jobs) shift; jobs="${1:?--jobs 缺少参数}" ;;
            --directory) shift; directory="${1:?--directory 缺少参数}" ;;
            --image) shift; image="${1:?--image 缺少参数}" ;;
            --full) full=1 ;;
            --docker) use_docker=1 ;;
            --yes) export RK_ASSUME_YES=1 ;;
            *) die "verify: 未知参数: $1" ;;
        esac
        shift
    done
    case "$target" in
        static|tests|patches|debs|image|candidate) ;;
        *) die "verify 目标缺失或无效（可用 static/tests/patches/debs/image/candidate）" ;;
    esac
    require_dir "$DIR" "（请先执行 w132d init）"
    require_file "$DIR/$TOOL" "（上游仓库不完整）"

    local -a a=(verify "$target")
    [[ -n "$directory" ]] && a+=(--directory "$directory")
    [[ -n "$image" ]] && a+=(--image "$image")
    (( full )) && a+=(--full)
    [[ "$target" == "patches" ]] && a+=(--jobs "$jobs")

    log_step "检查 W132D: $target"
    if (( use_docker )); then
        log_info "使用官方检查容器 w132d-check（首次需先构建镜像）"
        log_info "  docker build -t w132d-check -f tools/docker/Dockerfile ."
        if [[ "${RK_DRY_RUN:-0}" != "1" ]] && ! have_cmd docker; then
            die "--docker 需要 docker 命令"
        fi
        run_in_logged "$DIR" "${RK_LOG_DIR}/w132d-verify-${target}-$(date +%Y%m%d-%H%M%S).log" \
            docker run --rm -v "$DIR:/work" -w /work w132d-check "$TOOL" "${a[@]}"
    else
        run_in_logged "$DIR" "${RK_LOG_DIR}/w132d-verify-${target}-$(date +%Y%m%d-%H%M%S).log" \
            "$TOOL" "${a[@]}"
    fi
    log_ok "检查完成: $target"
}

# ------------------------------------------------------------------------------
# flash
# ------------------------------------------------------------------------------
do_flash() {
    local tag="" execute=0 verify_only=0
    while (($#)); do
        case "$1" in
            --tag) shift; tag="${1:?--tag 缺少参数}" ;;
            --tag=*) tag="${1#*=}" ;;
            --execute) execute=1 ;;
            --verify-only) verify_only=1 ;;
            --yes) export RK_ASSUME_YES=1 ;;
            *) die "flash: 未知参数: $1" ;;
        esac
        shift
    done

    local label="${tag:-latest}"
    local base
    if [[ -n "$tag" ]]; then
        base="$RK_W132D_RELEASE_BASE/$tag"
    else
        base="$RK_W132D_RELEASE_LATEST"
    fi
    local rdir="$RK_DOWNLOAD_DIR/w132d-release/$label"
    local sumfile="$rdir/SHA256SUMS"
    local zip="$rdir/w132d-flash.zip"
    local dest="$RK_W132D_FLASH_DIR/$label"

    log_step "下载 W132D 官方刷写包 ($label)"
    log_info "来源: $base"
    ensure_dir "$rdir"
    # 摘要清单每次都刷新（体积很小），压缩包存在且校验通过则复用
    run curl -fL --retry "$RK_DOWNLOAD_RETRIES" --connect-timeout 20 -o "$sumfile" "$base/SHA256SUMS"
    download "$base/w132d-flash.zip" "$zip"

    if [[ "${RK_DRY_RUN:-0}" != "1" ]]; then
        local expected
        expected="$(awk '{n=$2; sub(/^\*/,"",n); if (n=="w132d-flash.zip") {print $1; exit}}' "$sumfile" 2>/dev/null || true)"
        [[ -n "$expected" ]] || die "SHA256SUMS 中没有 w132d-flash.zip 条目，请确认 Release 资产完整"
        log_info "期望 SHA256: $expected"
        echo "$expected  $zip" | sha256sum -c - >/dev/null || die "SHA256 校验失败，拒绝解压/刷写: $zip"
        log_ok "SHA256 校验通过"
    else
        log_warn "[预演] 跳过 SHA256 校验"
    fi

    log_step "解压刷写包"
    ensure_dir "$dest"
    if have_cmd unzip || [[ "${RK_DRY_RUN:-0}" == "1" ]]; then
        run unzip -o -q "$zip" -d "$dest"
    else
        die "缺少 unzip，请先安装（或执行 check-host --install）"
    fi
    local flashdir="$dest" flash
    if [[ "${RK_DRY_RUN:-0}" == "1" ]]; then
        log_warn "[预演] 跳过刷写包结构检查"
    else
        flash="$(find "$dest" -maxdepth 3 -type f -name flash.sh -print -quit 2>/dev/null || true)"
        [[ -n "$flash" ]] || die "解压后未找到 flash.sh，刷写包结构可能已变化；请检查 $dest"
        flashdir="$(dirname "$flash")"
    fi
    log_ok "刷写目录: $flashdir"
    if [[ "${RK_DRY_RUN:-0}" != "1" ]]; then
        chmod +x "$flash"
        while IFS= read -r -d '' t; do chmod +x "$t"; done < <(
            find "$flashdir/tools" -type f -name rkdeveloptool -print0 2>/dev/null || true)
        for f in flash-manifest.json loader.bin image-head.bin image-system.bin; do
            [[ -f "$flashdir/$f" ]] || log_warn "刷写包缺少 $f（上游 dry-run 会检查）"
        done
    fi

    log_step "刷写包自检（不访问 USB）"
    run_in "$flashdir" ./flash.sh --dry-run

    if (( verify_only )); then
        log_step "只读回读校验（不写入、不重启）"
        if [[ "${RK_DRY_RUN:-0}" != "1" ]]; then
            confirm_dangerous "VERIFY" "即将执行 sudo ./flash.sh --verify-only，仅比较已写入数据。"
        else
            log_warn "[预演] 跳过危险确认"
        fi
        run_in "$flashdir" sudo ./flash.sh --verify-only
        return 0
    fi

    if (( ! execute )); then
        echo
        log_warn "预演模式，未刷写。确认自检输出 FLASH_DRY_RUN_OK 后再加 --execute。"
        log_info "首次启动：root / 1234，需改密并创建普通用户；详见 docs/10-W132D主线Linux.md"
        return 0
    fi

    cat <<'EOF'

进入 USB 下载模式（上游 docs/install.md）：
  1) 设备断电，按住 Reset 针孔按键（HDMI / USB 3.0 口旁）
  2) 保持按住，接通电源并用 USB 数据线直连电脑，约 5 秒后松开
  3) 电脑只连接一台 Rockchip 设备，刷写过程中保持供电
  刷写会替换系统和分区表，仅保留 vendor storage / RKSS 区间。

EOF
    if [[ "$(detect_platform)" == "wsl2" ]]; then
        log_warn "当前是 WSL2：WSL2 默认内核未启用 USB_STORAGE，rkdeveloptool 的 USB 直通未获上游验证"
        log_warn "强烈建议在原生 Ubuntu x86_64 物理机上执行刷写；继续前请确认 USB 设备已成功直通"
    fi
    if [[ "${RK_DRY_RUN:-0}" != "1" ]]; then
        confirm_dangerous "FLASH" \
            "即将执行 sudo ./flash.sh，W132D 的系统与分区表会被覆盖、不可撤销！
  目标: $flashdir  ($label)"
    else
        log_warn "[预演] 跳过危险确认"
    fi
    run_in "$flashdir" sudo ./flash.sh
    log_ok "刷写流程结束（请确认上游输出 FLASH_OK 后再断电）"
}

# ------------------------------------------------------------------------------
# status
# ------------------------------------------------------------------------------
do_status() {
    log_step "W132D 路线状态"
    log_info "上游仓库 : $RK_W132D_REPO ($RK_W132D_BRANCH)"
    if [[ -d "$DIR" ]]; then
        log_ok "源码目录 : $DIR"
        log_info "当前提交 : $(cd "$DIR" && git rev-parse --short HEAD 2>/dev/null || echo '?')"
        [[ -f "$DIR/$TOOL" ]] && log_ok "构建入口 : $DIR/$TOOL" || log_warn "缺少 $TOOL"
        local v
        v="$(manifest_version || echo '')"
        [[ -n "$v" ]] && log_info "manifest : $v" || log_warn "尚无 out/manifest.json（先跑 w132d fetch）"
        if [[ -n "$v" && -d "$DIR/out/$v" ]]; then
            log_info "产物目录 : $DIR/out/$v"
            find "$DIR/out/$v" -maxdepth 1 -type f -printf '    %f  %s bytes\n' 2>/dev/null | head -20 || true
        fi
    else
        log_warn "源码目录缺失: $DIR（先跑 w132d init）"
    fi
    if [[ -d "$RK_W132D_FLASH_DIR" ]]; then
        log_ok "刷写包目录: $RK_W132D_FLASH_DIR"
        find "$RK_W132D_FLASH_DIR" -maxdepth 2 -type f -name flash.sh -print 2>/dev/null | sed 's/^/    /'
    else
        log_warn "尚无刷写包（w132d flash 会下载）"
    fi
    echo
    check_build_env
}

# ------------------------------------------------------------------------------
case "$ACTION" in
    init)   do_init "$@" ;;
    fetch)  do_fetch "$@" ;;
    build)  do_build "$@" ;;
    verify) do_verify "$@" ;;
    flash)  do_flash "$@" ;;
    status) do_status "$@" ;;
    *)      log_error "未知动作: $ACTION"; usage; exit 1 ;;
esac
