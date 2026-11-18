# Luckfox Lyra B 的 ILI9488 主屏

把底座上的 ILI9488 做成 Luckfox Lyra 的 Linux 控制台。当前这台板子从 SD 卡启动 Ubuntu 22.04，内核 6.1.99，ADB 可直接进 root。出厂内核没有 `panel-mipi-dbi`，也没有 GPIO 背光驱动，只换设备树点不亮这块屏，需要重新编译内核。

## 套到 SDK

```sh
./apply.sh /path/to/luckfox-lyra-sdk
```

脚本会打上补丁，把 `firmware/ili9488.bin` 放进 `kernel-6.1/firmware/`，并把 `configs/ili9488.fragment` 合并进 Lyra 的 defconfig。202610 的 SDK 已经没有单独的 `rk3506g-luckfox-lyra-sd.dts`，屏写在 `rk3506g-luckfox-lyra.dts` 里。旧树里如果还有那份 SD 设备树，脚本仍会给它打 `0003`。

这台板从 SD 卡启动，根文件系统是 `root=/dev/mmcblk0p3`。202610 的设备树不再写 root，现有启动程序会自己补上。编译时 lunch 选 `luckfox_lyra_buildroot_sdmmc`，只编内核，不要把 Buildroot 根文件系统刷进这张卡。

Ubuntu 镜像里 `getty@tty1` 已经启用，不用再改 Buildroot 的 inittab。

## 和移植说明不一致的两处

这两处按 6.1 的 `panel-mipi-dbi` 源码改过，照文档原文写会在探测时失败或颜色反掉。

- 像素格式用 `b6x2g6x2r6x2`。驱动把 `DRM_FORMAT_RGB888` 按小端、8 位一字送出去，线上就是 B、G、R。初始化命令 `0x36 = 0x28` 已经把屏设成 BGR。6.1 补丁不接受文档里的 `r6x2g6x2b6x2`。
- `hsync-len` 和 `vsync-len` 都是 0。这个驱动要求同步宽度不要超出分辨率，写成 1 会报 `panel-timing out of bounds`。

SPI 功能号按 RK3506 的 4 位 iomux 计算：TRM 序号加 15。和现有 I2C2 节点（SCL 19 写成 34）同一套算法，所以 CLK / MOSI / CSN0 是 82 / 83 / 85。
