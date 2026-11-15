# W132D 板级兼容性修复

ZTE Cloud Computer W132D（RK3528）在运行非原厂 Linux 时无法启动的问题定位与修复记录。

- **硬件**：ZTE W132D，RK3528（4×Cortex-A53），eMMC 29.3GiB，UWE5621DS Wi-Fi
- **系统**：Armbian 7.2.11-edge-rockchip64 / 7.3.4
- **现象**：HDMI 全程黑屏，无网络，USB 不枚举，但 MaskROM 可正常进入
- **结论**：全部是设备树 / 内核参数配置缺陷，硬件本身完好

---

## 1. 问题一：GPIO 电源域导致启动早期 panic

### 症状

内核启动到 2.04 秒 panic：

```
[2.033937] rockchip-gpio ff610000.gpio: probed /pinctrl/gpio@ff610000
[2.044774] Internal error: synchronous external abort: 0000000096000010
[2.045436] lr : reset_control_assert+0x8c/0x208
[2.045531] Kernel panic - not syncing: Asynchronous SError Interrupt
```

### 原因

W132D 的 DTB 中，GPIO 控制器引用了电源域：

```dts
gpio@ffaf0000 { ... power-domains = <&power 8>; };
gpio@ffb00000 { ... power-domains = <&power 7>; };
gpio@ffb10000 { ... power-domains = <&power 8>; };
gpio@ffb20000 { ... power-domains = <&power 6>; };
```

`gpio@ff610000` 探测完成后，下一个 `gpio@ffaf0000` 需要上电 domain 8，而该域在此硬件上无法上电，访问 PMU 寄存器即触发 SError。

### 修复

移除这四个 GPIO 节点的 `power-domains` 属性。

> 注：rock-2a 参考板配法相同却能正常工作，说明是 W132D 这块板子的 domain 8 供电异常，而非配置写错。

---

## 2. 问题二：eMMC 缺 `vqmmc-supply` 导致高速模式超时

### 症状

系统能启动到用户空间，但 19.6 秒左右 eMMC 报错：

```
[2.660469] mmc0: new HS400 Enhanced strobe MMC card at address 0001
[19.679369] mmc0: Timeout waiting for hardware interrupt.
```

随后上层进程卡死，表现为 RCU stall。

### 原因

`mmc@ffbf0000` 声明了 `mmc-hs200-1_8v` / `mmc-hs400-1_8v` / `mmc-hs400-enhanced-strobe`，**却没有 `vqmmc-supply`**。

HS200/HS400 规范只支持 1.8V 信号电平。没有该引用，内核按 3.3V 时序驱动实际为 1.8V 的 VCCQ 接口，低速阶段尚可凑合，提速后时序完全错位。

### 修复

在 `mmc@ffbf0000` 节点补上 1.8V 供电引用：

```dts
vqmmc-supply = <&vdd_1v8_s3>;
```

（W132D 的 `vdd_1v8_s3` = 1.80V 固定 regulator）

### 验证

修复后 HS400 Enhanced Strobe 稳定运行：

```
[1.944590] mmc0: new HS400 Enhanced strobe MMC card at address 0001
$ dd if=/dev/zero of=/tmp/t bs=1M count=300 conv=fdatasync
300 MiB copied, 0.728557 s, 432 MB/s
$ dmesg | grep -c Timeout
0
```

**降频（HS400→HS200→DDR52）只是掩盖症状，无法根治。** 该问题与频率无关，纯粹是电压配置缺失。

---

## 3. 问题三：内核回收 GPIO 时钟导致 SError

### 症状

移除 GPIO 的 `power-domains` 后，系统运行中任意 GPIO 写入都会崩溃：

```
[11.815325] pc : _raw_spin_unlock_irqrestore+0x18/0x58
[11.815339] lr : rockchip_gpio_set+0x9c/0x110
[11.815433] Kernel panic - not syncing: Asynchronous SError Interrupt
```

### 原因

GPIO 不再引用电源域后，内核的时钟/电源域回收机制把 GPIO 时钟当作"无人使用"关闭，访问其寄存器即触发外部中止。

### 修复

内核命令行追加：

```
clk_ignore_unused pd_ignore_unused
```

阻止内核回收"看起来未使用"的时钟和电源域，GPIO 始终保持可访问。

---

## 4. 问题四：用户空间服务与模块问题

### 4.1 zram 配置超时

```
[39.647630] systemd[1]: armbian-zram-config.service: start operation timed out.
[69.547361] rcu: INFO: rcu_preempt detected stalls on CPUs/tasks:
```

屏蔽服务：

```bash
systemctl mask armbian-zram-config.service
systemctl mask armbian-ramlog.service
```

### 4.2 模块加载 oops

以下模块在探测时访问 GPIO 或依赖不存在的硬件，触发 oops：

| 模块 | 说明 |
|---|---|
| `gpio_ir_recv` | 红外接收，访问 GPIO |
| `snd_soc_simple_card` / `snd_soc_rockchip_pdm` / `snd_soc_rockchip_sai` | 音频，访问 GPIO |
| `snd_soc_rk3528` / `snd_soc_es7202` | 音频 codec，probe 时拉 GPIO（功放使能） |

处理方式见 `overlays/rootfs/etc/modprobe.d/w132d-blacklist.conf`。

---

## 5. Wi-Fi 恢复（重要陷阱）

### 现象

移除黑名单后 `wlan0` 仍不出现，`ip link` 只有 `lo` 和 `eth0`，同时 systemd 报 `sys-subsystem-net-devices-wlan0.device` 超时。

### 原因

`/etc/modprobe.d/` 中残留了 `install` 规则：

```
install sprdwl_ng /bin/true
```

`install` 规则比 `blacklist` 更彻底 —— 它让 modprobe 直接执行 `/bin/true`，模块永远无法加载。
**只删 `blacklist` 行不够，`install` 行必须一起删除。**

### 修复

```bash
sed -i -e '/sprdwl_ng/d' -e '/uwe5622_bsp_sdio/d' -e '/sprdbt_tty/d' \
    /etc/modprobe.d/blacklist-w132d.conf
modprobe sprdwl_ng
```

恢复后 `wlan0` 出现，正常连接 Wi-Fi（实测 IP `192.168.31.164`，SSH 可用）。

---

## 6. 完整的设备树改动汇总

以 `rk3528-w132d.dtb` 反编译得到的 dts 为基准：

```diff
 	mmc@ffbf0000 {
 		...
-		power-domains = <&power 8>;
 		...
 		cap-mmc-highspeed;
 		mmc-hs200-1_8v;
 		mmc-hs400-1_8v;
 		mmc-hs400-enhanced-strobe;
 		no-sd;
 		no-sdio;
 		non-removable;
+		vqmmc-supply = <&vdd_1v8_s3>;
 	};

 	gpio@ffaf0000 {
-		power-domains = <&power 8>;
 	};
 	gpio@ffb00000 {
-		power-domains = <&power 7>;
 	};
 	gpio@ffb10000 {
-		power-domains = <&power 8>;
 	};
 	gpio@ffb20000 {
-		power-domains = <&power 6>;
 	};
```

内核命令行（`extlinux.conf` 的 `append` 行末尾追加）：

```
clk_ignore_unused pd_ignore_unused
```

---

## 7. 修改 DTB 的通用流程

```bash
# 1. 提取 boot 分区（image-system.bin 内偏移 11MiB，大小 512MiB）
dd if=image-system.bin of=bootfs.img bs=1m skip=11 count=512

# 2. 挂载并取出 dtb
hdiutil attach bootfs.img -mountpoint /tmp/mnt -nobrowse    # macOS
cp /tmp/mnt/dtb/rockchip/rk3528-w132d.dtb ./orig.dtb

# 3. 反编译 / 修改 / 编译
dtc -I dtb -O dts orig.dtb -o w132d.dts
#   ... 编辑 w132d.dts ...
dtc -I dts -O dtb w132d.dts -o new.dtb

# 4. 放回并回写镜像
cp new.dtb /tmp/mnt/dtb/rockchip/rk3528-w132d.dtb && sync
hdiutil detach /tmp/mnt
dd if=bootfs.img of=image-system.bin bs=1m seek=11 conv=notrunc

# 5. 重算 manifest 中的 sha256，否则 flash.py 拒绝烧写
```

> 注意：`flash.py` 的校验只是自证 —— 它用 manifest 里记录的 sha256 与当前文件比对，
> 而这个值需要手动更新，因此无法发现内容层面的错误。

---

## 8. 排查工具提示

- **串口**：UART0 = `GPIO4_C7`(RX) / `GPIO4_D0`(TX)，115200（内核）/ 1500000（U-Boot）
- macOS 设置 1500000 须用 `IOSSIOSPEED` ioctl（Python `termios` 无 `B1500000`），
  但 USB CDC 串口在该速率下不准，U-Boot 输出会呈 `U-oo|`、`Loa|yng` 之类错位
- `stty -f` 对串口无效（每次 open 重置为 9600），必须用 Python `termios` 在 open 后设置
- **MaskROM 进入方式**：断电 → 按住 USB 3.0 口旁针孔 → 接电源 → 5 秒后松手。
  HDMI 旁边的针孔是错的（会进入原厂升级模式）
