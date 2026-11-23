### AnyKernel3 - REDMI K90 (annibale) GKI 6.6 + FinaSU

properties() { '
kernel.string=REDMI K90 annibale | GKI android15-6.6 | FinaSU Built-In
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=annibale
device.name2=2510DRK44C
device.name3=REDMI K90
supported.versions=
supported.patchlevels=
'; }

### 分区设置
# K90 是 GKI 2.0 + A/B：内核在 boot，通用 ramdisk 在 init_boot，厂商资源在 vendor_boot
# Built-In 只替换 boot 里的 kernel，不动 init_boot / vendor_boot
block=/dev/block/bootdevice/by-name/boot;
is_slot_device=auto;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;

### 不要修改以下部分
. tools/ak3-core.sh;

setup_ak3;
split_boot;
flash_boot;
### end
