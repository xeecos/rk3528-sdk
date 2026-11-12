#!/usr/bin/env bash
# ==============================================================================
# RK3528 SDK 构建工具 —— 统一入口
#
# 依据 FriendlyELEC WiKi《Template:RK3528-BuildFromSource/zh》与
# sd-fuse_rk3528 (kernel-6.1.y) 官方 README 整理、脚本化。
#
# 支持平台（只支持这两个，见 README §3）：
#   1) 原生 Ubuntu 20.04/22.04/24.04 x86_64
#   2) Windows 11 WSL2 中的 Ubuntu 22.04/24.04（VERSION 必须为 2）
# 其它平台不测试、不修兼容问题；WSL1 会被 require_linux 直接拒绝。
# 用法：./rk3528-sdk.sh help
# ==============================================================================

set -euo pipefail
_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# 配置加载前先扫一遍全局开关，保证 --conf / --dry-run 能影响配置本身
_pre=("$@")
# help/config/status 不需要创建工作目录
case "${_pre[0]:-}" in
    -h|--help|help|config|status) export RK_INIT_DIRS=0 ;;
esac
for ((_i = 0; _i < ${#_pre[@]}; _i++)); do
    case "${_pre[$_i]}" in
        --dry-run)   export RK_DRY_RUN=1 ;;
        --yes|-y)    export RK_ASSUME_YES=1 ;;
        --conf=*)    export RK_CONF="${_pre[$_i]#*=}" ;;
        --conf)      _i=$((_i + 1)); if (( _i < ${#_pre[@]} )); then export RK_CONF="${_pre[$_i]}"; fi ;;
    esac
done

# shellcheck source=lib/config.sh
source "${_ROOT}/lib/config.sh"

usage() {
    cat <<EOF
${C_BOLD}RK3528 SDK 构建工具${C_OFF}
用法: ./rk3528-sdk.sh [全局选项] <命令> [参数...]

${C_BOLD}支持平台${C_OFF}
  原生 Ubuntu 20.04/22.04/24.04 x86_64  |  Win11 WSL2 中的 Ubuntu 22.04/24.04
  WSL1 会被拒绝；其它平台不测试、不修兼容问题（WSL2 见 docs/09-WSL2构建指南.md）

${C_BOLD}全局选项${C_OFF}
  --dry-run          只打印将要执行的命令，不真正执行
  --yes              跳过普通交互确认（危险操作仍需手工输入确认串）
  --conf FILE        指定额外配置文件（在 sdk.conf / sdk.local.conf 之后加载）
  -h, --help         显示本帮助

${C_BOLD}环境准备${C_OFF}
  check-host [--install]        检查主机系统/依赖/磁盘；--install 时用 apt 安装缺失包
  install-toolchain             安装 11.3-aarch64 交叉编译器到 ${RK_TOOLCHAIN_ROOT}
  config                        打印当前生效配置
  status                        查看源码、工具链、产物状态

${C_BOLD}方案 A：FriendlyWrt 25.12 全量工程（repo 多仓库）${C_OFF}
  fw-init [--force]             下载源码：repo init -b ${RK_FW_MANIFEST_BRANCH} -m ${RK_FW_MANIFEST_FILE}
  fw-build all                  首次全量编译（${RK_FW_BOARD_MK}），生成 SD 镜像
  fw-build docker               全量编译 docker 版（${RK_FW_BOARD_MK_DOCKER}）
  fw-build uboot|kernel|friendlywrt   单独编译某一组件
  fw-build sd-img|emmc-img      重新打包 SD / eMMC(eflasher) 镜像
  fw-build menuconfig           修改 FriendlyWrt 配置（make menuconfig）
  fw-build rebuild              二次编译：清 tmp -> make -> 重打两种镜像
  fw-build single               单线程排错编译 (make -j1 V=s)
  fw-build clean|cleanall       清理旧镜像 / 彻底清理

${C_BOLD}方案 B：手工编译内核与 U-Boot（不依赖 sd-fuse）${C_OFF}
  kernel-build [--friendlywrt] [--menuconfig] [--jobs N]
                                 编译 linux-v6.1.y，产出 kernel.img / resource.img / out-modules
  uboot-build                    编译 u-boot v2017.09，产出 uboot.img / trust.img / MiniLoaderAll.bin

${C_BOLD}方案 C：sd-fuse 脚本化编译与打包${C_OFF}
  sdfuse-init [OS] [--images FILE|URL] [--with-eflasher]
                                 克隆 sd-fuse + 准备分区镜像文件
  sdfuse-build kernel|headers|uboot [OS]
                                 编译内核 / 内核头文件 / uboot 并自动更新 OS 目录
  sdfuse-image sd|emmc [OS]     生成 SD 固件 / SD-to-eMMC 卡刷固件
  sdfuse-image fuse [OS] --device /dev/sdX
                                 直接烧写 SD 卡（高危，需二次确认）

${C_BOLD}烧录与更新${C_OFF}
  install-board                 在目标板上用 dd 更新 resource/kernel/uboot 分区（高危）
  flash-loader                  主机上用 upgrade_tool 线刷（需开发板进入 loader 模式）

${C_BOLD}其它${C_OFF}
  clean [all|images|logs]       清理本工具生成的产物
  help                          显示本帮助

${C_BOLD}示例${C_OFF}
  ./rk3528-sdk.sh check-host --install
  ./rk3528-sdk.sh install-toolchain
  ./rk3528-sdk.sh fw-init && ./rk3528-sdk.sh fw-build all
  RK_WORKSPACE=/mnt/data/rk3528 ./rk3528-sdk.sh sdfuse-init ubuntu-noble-core-arm64
  ./rk3528-sdk.sh sdfuse-build kernel ubuntu-noble-core-arm64
  ./rk3528-sdk.sh sdfuse-image sd ubuntu-noble-core-arm64

文档见 docs/ 目录；默认 OS 为 ${RK_DEFAULT_OS}。
EOF
}

# -------- 提取全局选项，其余原样传给子脚本 --------
_args=()
while (($#)); do
    case "$1" in
        --dry-run)      export RK_DRY_RUN=1 ;;
        --yes|-y)       export RK_ASSUME_YES=1; _args+=("--yes") ;;
        --conf)         shift; [[ $# -gt 0 ]] || die "--conf 缺少参数"; export RK_CONF="$1" ;;
        --conf=*)       export RK_CONF="${1#*=}" ;;
        -h|--help|help) usage; exit 0 ;;
        *)              _args+=("$1") ;;
    esac
    shift
done
set -- "${_args[@]}"
(($#)) || { usage; exit 0; }

cmd=$1; shift

# -------- 内置命令 --------
case "$cmd" in
    config)
        echo "生效配置："
        print_config
        exit 0 ;;
    status)
        log_step "环境状态"
        case "$(detect_platform)" in
            wsl2)  log_ok   "平台: Windows WSL2（受支持）" ;;
            wsl1)  log_warn "平台: WSL1（不受支持，请执行 wsl --set-version <distro> 2）" ;;
            linux) log_ok   "平台: 原生 Linux（Ubuntu x86_64 受支持）" ;;
            *)     log_warn "平台: 非 Linux / 非目标平台（仅预演）" ;;
        esac
        print_config
        echo
        local_dirs=("$RK_FW_DIR" "$RK_SDFUSE_DIR" "$RK_KERNEL_SRC" "$RK_UBOOT_SRC" "$RK_RKBIN_SRC" "$RK_TOOLCHAIN_BIN")
        for d in "${local_dirs[@]}"; do
            if [[ -d "$d" ]]; then
                printf '  %s[存在]%s %-60s %s\n' "$C_GREEN" "$C_OFF" "$d" "$(human_size "$d")"
            else
                printf '  %s[缺失]%s %s\n' "$C_YELLOW" "$C_OFF" "$d"
            fi
        done
        echo
        log_step "产物 ($RK_OUTPUT_DIR / sd-fuse out)"
        find "$RK_OUTPUT_DIR" "${RK_SDFUSE_DIR}/out" -maxdepth 2 -type f \
            \( -name '*.img' -o -name '*.img.gz' -o -name '*.deb' -o -name '*.tgz' \) \
            2>/dev/null | head -40 || true
        exit 0 ;;
    clean)
        exec bash "${_ROOT}/scripts/clean.sh" "$@" ;;
    help)
        usage; exit 0 ;;
esac

# -------- 命令到脚本的映射 --------
declare -A _SCRIPTS=(
    [check-host]=check-host.sh
    [install-toolchain]=install-toolchain.sh
    [fw-init]=fw-init.sh
    [fw-build]=fw-build.sh
    [kernel-build]=kernel-build.sh
    [uboot-build]=uboot-build.sh
    [sdfuse-init]=sdfuse-init.sh
    [sdfuse-build]=sdfuse-build.sh
    [sdfuse-image]=sdfuse-image.sh
    [install-board]=install-to-board.sh
    [flash-loader]=flash-loader.sh
)

if [[ -z "${_SCRIPTS[$cmd]:-}" ]]; then
    log_error "未知命令: $cmd"
    echo "运行 ./rk3528-sdk.sh help 查看可用命令" >&2
    exit 1
fi

_script="${_ROOT}/scripts/${_SCRIPTS[$cmd]}"
[[ -f "$_script" ]] || die "脚本缺失: $_script"
exec bash "$_script" "$@"
