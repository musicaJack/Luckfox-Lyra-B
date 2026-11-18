# Linux 上编译 ILI9488 内核

在 Ubuntu 22.04 x86_64 上编。SDK 的交叉编译器和 `resource_tool` 都是 Linux x86_64 程序，Apple 芯片的 Mac 不能编。

编出来的是启动镜像 `boot.img`。不要编根文件系统，不要把 Buildroot 刷进现在这张 SD 卡。

## 1. 准备编译机

Ubuntu 22.04 LTS，架构必须是 x86_64。磁盘至少留出 40 GB。编译过程中不要对 SDK 目录滥用 `sudo`。

```sh
sudo apt-get update
sudo apt-get install -y git ssh make gcc g++ python2 python-is-python3 \
  libssl-dev liblz4-tool expect gawk texinfo chrpath diffstat bison flex \
  fakeroot cmake unzip device-tree-compiler ncurses-dev bzip2 curl file \
  rsync bc cpio wget patch
sudo ln -sf /usr/bin/python2 /usr/bin/python
python --version
```

这里的 `python` 要指向 Python 2。SDK 自带的 `repo` 是 Python 2 脚本。

## 2. 下载 SDK

文件名 `Luckfox_Lyra_SDK_202610.tar.gz`，大约 3.0 GB。幸狐资料页提供百度网盘和 Google Drive：

- 百度网盘：https://pan.baidu.com/s/1oPmnE3TLVCjPfUDtXG7rvw?pwd=p2kr
- Google Drive：https://drive.google.com/drive/folders/1OHgViTQN34K7PTiB7fiToUk_arG-vtcP

SHA256：

```text
74f1379cbf4968f566b3a5385010ead076cc65bbee838b83e72a5f996494b3c9
```

```sh
cd ~
mkdir -p lyra-sdk && cd lyra-sdk
# 把压缩包放到这个目录后：
sha256sum Luckfox_Lyra_SDK_202610.tar.gz
```

哈希必须和上面那一行一致。这个压缩包是 repo 镜像，解压后还要做一次本地检出，不会马上出现 `kernel-6.1` 目录。

```sh
tar -xzf Luckfox_Lyra_SDK_202610.tar.gz
.repo/repo/repo sync -l
test -d kernel-6.1 && echo "kernel tree ready"
```

`repo sync -l` 只使用包里的本地仓库，不访问外网。

## 3. 打上 ILI9488 补丁

```sh
cd ~
git clone https://github.com/musicaJack/Luckfox-Lyra-B.git
cd Luckfox-Lyra-B
chmod +x apply.sh
./apply.sh ~/lyra-sdk
```

成功时会看到：

- `0001`、`0002` 已打上
- 打印 `no rk3506g-luckfox-lyra-sd.dts`，这是 202610 的正常情况
- `ili9488.bin` 复制到 `kernel-6.1/firmware/`
- 配置合并进 `kernel-6.1/arch/arm/configs/rk3506_luckfox_defconfig`

可以再确认这两行还在：

```sh
grep ili9488 ~/lyra-sdk/kernel-6.1/arch/arm/configs/rk3506_luckfox_defconfig
grep b6x2g6x2r6x2 ~/lyra-sdk/kernel-6.1/arch/arm/boot/dts/rk3506g-luckfox-lyra.dts
```

## 4. 只编译内核

```sh
cd ~/lyra-sdk
./build.sh luckfox_lyra_buildroot_sdmmc_defconfig
./build.sh kernel
```

如果 `./build.sh` 仍弹出菜单，按下面选，不要选 SPI NAND，不要选别的板型：

| 问题 | 选择 |
| --- | --- |
| 硬件版本 | `0`，RK3506G_Luckfox_Lyra |
| 启动媒介 | `0`，SD_CARD |
| 系统版本 | `0`，Buildroot |

对应的配置名是 `luckfox_lyra_buildroot_sdmmc_defconfig`。这份配置使用设备树 `rk3506g-luckfox-lyra`，内核 defconfig 是 `rk3506_luckfox_defconfig`。202610 的菜单里没有 Ubuntu。选 Buildroot 只是为了用同一份内核配置，不要接着编 rootfs。

不要执行：

```sh
./build.sh
./build.sh rootfs
./build.sh firmware
```

内核编完后，启动镜像在：

```text
output/firmware/boot.img
```

有的版本也会放到 `rockdev/boot.img`，两者是同一个文件的链接。把这个 `boot.img` 拷回 Mac 或留在编译机上，先不要往板子上写。

## 5. 编译完成后检查

`boot.img` 应该是 FIT 镜像，开头 4 字节是 `d0 0d fe ed`。体积和现在的启动分区接近，现在的分区大约 12 MB。如果编出来有几百 MB，那就是打进了根文件系统，不要刷。

```sh
ls -lh output/firmware/boot.img
xxd -l 16 output/firmware/boot.img
```

## 6. 刷写时只换启动分区

这一步等 `boot.img` 确认过再做。现有 SD 卡的启动分区是 `/dev/mmcblk0p2`。刷之前先从板子上再拉一份备份。Mac 上已有一份 2026-11-18 的备份，路径是 `/Users/shmusica.mj/Projects/code/luckfox-sdk-202610/mmcblk0p2.img.stock`，那份不在 Git 仓库里。

板子通过 ADB 操作时，厂商号要写进 `~/.android/adb_usb.ini`：

```text
0x2207
```

只把 `boot.img` 写入 `mmcblk0p2`。不要写 `mmcblk0p3`，那是 Ubuntu 根文件系统。写坏启动分区时，用备份按同样方式写回 `mmcblk0p2`。

串口在排针 1（TX）和排针 2（RX）。Type-C 只有 RNDIS 和 ADB，新内核如果起不来，不能靠 Type-C 把备份写回去，需要把 SD 卡拿下来用读卡器恢复。
