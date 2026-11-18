# Luckfox Lyra B 把 ILI9488 当作 Linux 主屏

查证日期：2026-11-18。目标是 Luckfox Lyra B（RK3506G2，板载 SPI NAND）。底座保持现在的 ILI9488 接线，不接摇杆，也不跑 2048。Lyra 从自己的系统启动，这块屏成为 Linux 控制台。

这份说明还没有在实机上点亮过。引脚来自幸狐官网 Lyra / Lyra B 引脚图，初始化命令来自本仓库 `src/hardware/display/ili9488/ili9488_driver.cpp`。改动发生在 Luckfox SDK 里，不在本仓库的 Pico 工程里。

本仓库的 `Game2350_st7306.uf2` 和 RP2040 的 UF2 不能拷到 Lyra 上。Lyra 不读 UF2。

## 1. 做到哪一步算完成

- 上电后背光亮，屏上出现内核文字，横屏，8×16 字体，大约 60 列 × 20 行。
- 完整启动日志留在 Pin 1 / Pin 2 的串口。屏幕只显示错误和登录提示。
- 能在这块屏上登录。

整屏刷新仍受 SPI 限制。320×480、RGB666、40 MHz 时，一整帧大约 92 毫秒。文字和控制台够用，动画和视频会顿。

## 2. 底座上哪些针要动

ILI9488 只占下面 6 根。电源、地、串口和 Pico 孔位一致，可以连着底座插上去。Pin 31、Pin 32 是 1.8V 的 SARADC，这套屏幕没有用到，保持空接。

| 信号 | 物理针 | Lyra 名称 | 设备树 GPIO | 复用 |
|---|---|---|---|---|
| RST | 20 | GPIO0_A2 | `&gpio0 RK_PA2` | GPIO，低电平复位 |
| 背光 | 21 | GPIO1_D3 | `&gpio1 RK_PD3` | GPIO，高电平亮 |
| CS | 22 | GPIO1_D2 | `&gpio1 RK_PD2` | RMIO30，SPI0_CSN0 |
| SCK | 24 | GPIO1_D1 | `&gpio1 RK_PD1` | RMIO29，SPI0_CLK |
| MOSI | 25 | GPIO1_C3 | `&gpio1 RK_PC3` | RMIO28，SPI0_MOSI |
| DC | 26 | GPIO1_C2 | `&gpio1 RK_PC2` | GPIO，高为数据、低为命令 |

没有 MISO。SPI 模式是模式 0（CPOL = 0，CPHA = 0），和现在的 Pico 驱动一样。

串口仍是 Pin 1（UART0_TX）和 Pin 2（UART0_RX），115200。排错时看这个口，不看屏幕。

## 3. 选对设备树

Lyra 的 SDK 用 `./build.sh lunch` 决定编哪一份设备树。Lyra B 的普通系统（板载 SPI NAND）对应 `kernel-6.1/arch/arm/boot/dts/rk3506g-luckfox-lyra.dts`，TF 卡启动对应 `rk3506g-luckfox-lyra-sd.dts`。只改 lunch 实际选中的那一份。

先关掉默认的 MIPI DSI，否则它会占住主显示：

```dts
&dsi { status = "disabled"; };
&dsi_dphy { status = "disabled"; };
&dsi_in_vop { status = "disabled"; };
&route_dsi { status = "disabled"; };
&dsi_panel { status = "disabled"; };
```

这些标签以当前 SDK 里的名字为准。某个标签不存在就跳过，不要为了凑齐去改 Ultra 的 dtsi。

## 4. 打开 SPI，挂上屏幕

在选中的 `.dts` 里增加背光和屏幕脚，并打开 `spi0`。`rm_io29_spi0_clk`、`rm_io28_spi0_mosi`、`rm_io30_spi0_csn0` 应已在 SDK 的 pinctrl 里。先确认：

```bash
grep -R "rm_io29_spi0_clk\|rm_io28_spi0_mosi\|rm_io30_spi0_csn0" kernel-6.1/arch/arm/boot/dts
```

三个符号都在，就直接引用。缺哪一个，就复制同文件里已有的 `rm_io*_spi0_*` 节点，只把引脚改成上表的 GPIO，第三格功能号保持和被复制的 SPI 信号一样（CLK、MOSI、CSN0 各用各的号）。

```dts
/ {
    backlight: backlight {
        compatible = "gpio-backlight";
        gpios = <&gpio1 RK_PD3 GPIO_ACTIVE_HIGH>;
        default-on;
    };
};

&pinctrl {
    ili9488 {
        ili9488_pins: ili9488-pins {
            rockchip,pins =
                <1 RK_PC2 RK_FUNC_GPIO &pcfg_pull_none>,
                <0 RK_PA2 RK_FUNC_GPIO &pcfg_pull_none>,
                <1 RK_PD3 RK_FUNC_GPIO &pcfg_pull_none>;
        };
    };
};

&spi0 {
    status = "okay";
    pinctrl-names = "default";
    pinctrl-0 = <&rm_io29_spi0_clk &rm_io28_spi0_mosi &rm_io30_spi0_csn0>;

    ili9488@0 {
        compatible = "ili9488", "panel-mipi-dbi-spi";
        reg = <0>;
        spi-max-frequency = <20000000>;
        write-only;

        pinctrl-names = "default";
        pinctrl-0 = <&ili9488_pins>;

        dc-gpios = <&gpio1 RK_PC2 GPIO_ACTIVE_HIGH>;
        reset-gpios = <&gpio0 RK_PA2 GPIO_ACTIVE_LOW>;
        backlight = <&backlight>;

        width-mm = <73>;
        height-mm = <49>;
        rotation = <0>;

        panel-timing {
            hactive = <480>;
            vactive = <320>;
            hback-porch = <0>;
            hfront-porch = <0>;
            hsync-len = <1>;
            vback-porch = <0>;
            vfront-porch = <0>;
            vsync-len = <1>;
            clock-frequency = <0>;
        };
    };
};
```

时钟先用 20 MHz。画面稳定以后再改到 `<40000000>`。排针加上屏幕排线，40 MHz 不一定稳。

`rotation = <0>` 是因为横屏已经写进下面的初始化命令 `0x36 = 0x28`。不要再在设备树里转 90 度，否则会转两次。字的方向不对时，只改初始化里的 `0x36`：本仓库的竖屏是 `0x48`，另一个横屏方向是 `0xE8`。

## 5. 初始化命令

命令和本仓库点亮这块屏时用的一致，只把 `0x36` 从竖屏的 `0x48` 改成横屏的 `0x28`。像素格式保持 `0x3A = 0x66`（RGB666，每像素 3 字节）。不要改成 `0x55`。

把下面存成 `ili9488.txt`：

```text
command 0x01
delay 200
command 0x11
delay 200
command 0x36 0x28
command 0x3A 0x66
command 0xC5 0x00 0x36 0x80
command 0xC2 0xA7
command 0xE0 0xF0 0x01 0x06 0x0F 0x12 0x1D 0x36 0x54 0x44 0x0C 0x18 0x16 0x13 0x15
command 0xE1 0xF0 0x01 0x05 0x0A 0x0B 0x07 0x32 0x44 0x44 0x0C 0x18 0x17 0x13 0x16
command 0x21
command 0x29
delay 50
```

用 [panel-mipi-dbi](https://github.com/notro/panel-mipi-dbi) 的 `mipi-dbi-cmd` 打成固件：

```bash
./mipi-dbi-cmd ili9488.bin ili9488.txt
```

驱动按第一个 `compatible` 找固件，文件名必须是 `ili9488.bin`。放进根文件系统的 `/lib/firmware/ili9488.bin`，跟随镜像一起烧进去。内核启动时要能读到它，不要只放在编译机上。

## 6. 内核配置

Lyra SDK 的内核是 6.1。`panel-mipi-dbi` 对 RGB666 的支持是后来才进主线的，6.1 里多半还没有。先看：

```bash
grep -n "r6x2g6x2b6x2" kernel-6.1/drivers/gpu/drm/drm_mipi_dbi.c kernel-6.1/drivers/gpu/drm/tiny/panel-mipi-dbi.c
```

没有这串字符串，就把主线里给 `drm_mipi_dbi` 增加 RGB666（`DRM_FORMAT_RGB888`，线上格式 `r6x2g6x2b6x2`）的那组改动移植到 6.1，并在面板节点上加上：

```dts
format = "r6x2g6x2b6x2";
```

颜色发红发蓝时，再试 `b6x2g6x2r6x2`。缺了这一步，驱动会按 RGB565 去送，这块屏会花。

`./build.sh kernel-config` 里打开，并编进内核（`=y`），不要只编成模块，否则控制台来得太晚：

- `CONFIG_SPI_ROCKCHIP`
- `CONFIG_DRM`
- `CONFIG_DRM_MIPI_DBI`
- `CONFIG_DRM_PANEL_MIPI_DBI`
- `CONFIG_DRM_FBDEV_EMULATION`
- `CONFIG_FRAMEBUFFER_CONSOLE`
- `CONFIG_FONT_8x16`
- `CONFIG_FONTS`

## 7. 启动参数和字号

在选中设备树的 `chosen` 里保留原来的 `earlycon`、`root=`、`rootwait`。串口控制台留着，再加屏幕控制台：

```text
console=tty1 console=ttyFIQ0 quiet loglevel=3 printk.time=0 fbcon=font:VGA8x16
```

`ttyFIQ0` 以这份设备树里原有的串口控制台名为准，不要把原来的串口名改掉。`quiet loglevel=3` 让屏幕不再刷完整启动日志。完整日志在串口上看 `dmesg`。

8×16 在横屏 480×320 上是 60 列 × 20 行。内核日志大多只折一次。若要凑满传统的 80 列，把字体换成 6×10，并打开对应的 `CONFIG_FONT_6x10`。字会小一圈。

Buildroot 的 `/etc/inittab` 里给这块屏一个登录口：

```text
tty1::respawn:/sbin/getty -L tty1 0 vt100
```

## 8. 编译和烧录

按幸狐文档选 lunch、编译、烧录。Lyra B 烧的是 SPI NAND 镜像，不是 TF 卡镜像，除非这次就是从卡启动。

烧录工具和分区以 [Luckfox Lyra 镜像烧录](https://wiki.luckfox.com/zh/Luckfox-Lyra) 当前页面为准。烧录会覆盖板上的系统。

## 9. 上电后怎么判断

串口 115200。屏幕上应先亮背光，随后出现黑底白字。字是横的，一行大约 60 个字符。

| 现象 | 处理 |
|---|---|
| 串口在跑，屏幕一直白或一直黑 | 看 `dmesg` 里有没有 `ili9488`、`panel-mipi-dbi`、找不到 `ili9488.bin`。固件不在 `/lib/firmware` 时驱动不会出图 |
| 有光，没有字 | 背光 GPIO 是好的。查 `tty1` 和 `DRM_FBDEV_EMULATION`，以及 DSI 是否还占着主显示 |
| 花屏、颜色错位 | 内核还在按 RGB565 发送。回到第 6 节，确认 RGB666 和 `0x3A = 0x66` |
| 字倒了或躺着 | 只改 `0x36`，在 `0x28` 和 `0xE8` 之间换。设备树 `rotation` 保持 0 |
| 高时钟下偶尔缺行 | 把 `spi-max-frequency` 降回 20000000 |

Pin 31 和 Pin 32 不要接 3.3V 的模拟信号。这次不用摇杆，这两脚就让它们空着。
