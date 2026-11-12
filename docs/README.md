# docs/

中文文档目录。建议阅读顺序：快速开始 → 对应路线 → 烧录 → 排错。

| 文档 | 内容 |
|---|---|
| [00-快速开始.md](00-快速开始.md) | 三种典型场景的完整命令序列 |
| [01-构建环境.md](01-构建环境.md) | 主机要求、依赖包、工具链、目录与容量规划、配置体系、镜像加速 |
| [02-FriendlyWrt编译.md](02-FriendlyWrt编译.md) | 路线 A：repo 工程、build.sh 目标、二次编译、单线程排错 |
| [03-内核与U-Boot编译.md](03-内核与U-Boot编译.md) | 路线 B：内核配置、模块处理、kernel/resource 打包、u-boot 产物 |
| [04-sd-fuse打包.md](04-sd-fuse打包.md) | 路线 C：分区镜像、环境变量、rootfs 定制、固件打包 |
| [05-烧录与更新.md](05-烧录与更新.md) | GPT 分区布局、dd 更新、线刷、SD 卡烧写、恢复 |
| [06-命令参考.md](06-命令参考.md) | 全部命令、参数、环境变量、退出码 |
| [07-故障排查.md](07-故障排查.md) | 常见错误与处理、提交问题时应收集的信息 |
| [08-Wiki流程对照.md](08-Wiki流程对照.md) | 官方 Wiki 每条命令 → 本工具命令逐条对应 |
| [09-WSL2构建指南.md](09-WSL2构建指南.md) | Windows / WSL2 安装、磁盘规划、ext4 路径、loop 设备、烧录回 Windows 侧 |

总览与版本矩阵见仓库根目录的 [README.md](../README.md)。

## 依据来源

- [FriendlyELEC WiKi — Template:RK3528-BuildFromSource/zh](https://wiki.friendlyelec.com/wiki/index.php/Template:RK3528-BuildFromSource/zh)
- [sd-fuse_rk3528 `kernel-6.1.y` README（中文）](https://github.com/friendlyarm/sd-fuse_rk3528/blob/kernel-6.1.y/README_cn.md)
- `friendlywrt_manifests/master-v25.12/rk3528.xml`、`friendlywrt_scripts/build.sh`、`prebuilts/README.md`
