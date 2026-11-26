### AnyKernel3 Ramdisk Mod Script -- osm0sis @ xda-developers ###
### Droidspaces kernel for Google Pixel 1 (sailfish / marlin)  ###

## AnyKernel setup
properties() { '
kernel.string=Droidspaces kernel 3.18 for Pixel 1 (sailfish/marlin) - crDroid 7.x
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=sailfish
device.name2=marlin
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; }

## AnyKernel install
boot_attributes() {
set_perm_recursive 0 0 755 644 $RAMDISK/*;
set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
}

# Pixel 1 (marlin/sailfish) is an A/B device. AnyKernel3 appends the active
# slot suffix automatically when IS_SLOT_DEVICE=1.
BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching (DO NOT REMOVE)
. tools/ak3-core.sh;

dump_boot;

# Keep the stock ramdisk untouched — only the kernel (Image.lz4-dtb) is replaced.
# Preserving the ramdisk keeps root (Magisk/KernelSU/APatch) and the crDroid init.

write_boot;
