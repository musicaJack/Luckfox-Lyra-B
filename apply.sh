#!/bin/sh
# Apply the ILI9488 console patches to a Luckfox Lyra SDK tree.
# Usage: ./apply.sh /path/to/luckfox-lyra-sdk
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SDK=${1:-}
if [ -z "$SDK" ] || [ ! -d "$SDK/kernel-6.1" ]; then
	echo "usage: $0 /path/to/luckfox-lyra-sdk" >&2
	exit 1
fi
SDK=$(CDPATH= cd -- "$SDK" && pwd)

python3 "$ROOT/firmware/pack.py"

apply_patch() {
	p=$1
	if patch -d "$SDK/kernel-6.1" -p1 --forward --dry-run < "$p" >/dev/null 2>&1; then
		patch -d "$SDK/kernel-6.1" -p1 --forward < "$p"
		echo "applied $(basename "$p")"
	elif patch -d "$SDK/kernel-6.1" -p1 --reverse --dry-run < "$p" >/dev/null 2>&1; then
		echo "already applied $(basename "$p")"
	else
		echo "failed to apply $(basename "$p")" >&2
		patch -d "$SDK/kernel-6.1" -p1 --forward < "$p"
		exit 1
	fi
}

apply_patch "$ROOT/patches/0001-drm-mipi-dbi-rgb666.patch"
apply_patch "$ROOT/patches/0002-arm-dts-luckfox-lyra-ili9488.patch"
if [ -f "$SDK/kernel-6.1/arch/arm/boot/dts/rk3506g-luckfox-lyra-sd.dts" ]; then
	apply_patch "$ROOT/patches/0003-arm-dts-luckfox-lyra-sd-ili9488.patch"
else
	echo "no rk3506g-luckfox-lyra-sd.dts; ILI9488 is in rk3506g-luckfox-lyra.dts"
fi

mkdir -p "$SDK/kernel-6.1/firmware"
cp "$ROOT/firmware/ili9488.bin" "$SDK/kernel-6.1/firmware/ili9488.bin"

merge_line() {
	file=$1
	line=$2
	key=${line%%=*}
	if [ "$key" = "CONFIG_EXTRA_FIRMWARE" ] && grep -q '^CONFIG_EXTRA_FIRMWARE=' "$file"; then
		cur=$(sed -n 's/^CONFIG_EXTRA_FIRMWARE="\(.*\)"/\1/p' "$file" | head -1)
		case " $cur " in
		*" ili9488.bin "*) ;;
		"")
			sed -i.bak 's/^CONFIG_EXTRA_FIRMWARE=.*/CONFIG_EXTRA_FIRMWARE="ili9488.bin"/' "$file"
			;;
		*)
			sed -i.bak "s/^CONFIG_EXTRA_FIRMWARE=\".*\"/CONFIG_EXTRA_FIRMWARE=\"$cur ili9488.bin\"/" "$file"
			;;
		esac
		rm -f "$file.bak"
		return
	fi
	if grep -q "^$key=" "$file" || grep -q "^# $key is not set" "$file"; then
		sed -i.bak "/^$key=/d; /^# $key is not set/d" "$file"
		rm -f "$file.bak"
	fi
	printf '%s\n' "$line" >> "$file"
}

merge_fragment() {
	file=$1
	[ -f "$file" ] || return 0
	while IFS= read -r line; do
		case $line in
		''|\#*) continue ;;
		esac
		merge_line "$file" "$line"
	done < "$ROOT/configs/ili9488.fragment"
	echo "config merged into $file"
}

# Kernel defconfigs named by the Lyra lunch entries, plus any already-present .config.
found=0
dir="$SDK/kernel-6.1/arch/arm/configs"
if [ -d "$dir" ]; then
	for file in "$dir"/*lyra* "$dir"/*rk3506*; do
		[ -f "$file" ] || continue
		case $file in
		*defconfig|*config)
			merge_fragment "$file"
			found=1
			;;
		esac
	done
fi
if [ -f "$SDK/kernel-6.1/.config" ]; then
	merge_fragment "$SDK/kernel-6.1/.config"
	found=1
fi
if [ "$found" -eq 0 ]; then
	echo "no Lyra defconfig found; fragment left at configs/ili9488.fragment" >&2
fi

echo "ILI9488 patches are in $SDK"
echo "This board boots Ubuntu from the SD card. Lunch luckfox_lyra_buildroot_sdmmc and build the kernel only."
echo "The 202610 SDK keeps root= out of the dts; the existing SD bootloader still supplies root=/dev/mmcblk0p3."
echo "tty1 getty is already enabled on that image; do not add a Buildroot inittab line."
