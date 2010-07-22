#!/bin/bash

if [ -z "$1" -o -z "$2" ]; then	
  echo "Please specify ISO path and patch path."
  exit 1
fi
CURDIR=$(pwd)
if [ -n "${2%%/*}" ]; then
  # related path
  PATCH="${CURDIR}/$2"
else
  PATCH=$2
fi

# copy microroot from iso
echo "Extracting microroot from ISO.."
mkdir -pv /mnt/iso
CDDEV=$(pfexec lofiadm -a $1)
mount -F hsfs $CDDEV /mnt/iso || exit 1
cp -v /mnt/iso/boot/x86.microroot x86.microroot.gz
gunzip x86.microroot.gz

# create new microroot
SIZE=${3:-128}
echo "Creating new microroot in ${SIZE}M."
mkdir -pv /mnt/microroot
dd if=/dev/zero of=x86.microroot-new bs=1M count=$SIZE
LODEV1=$(lofiadm -a x86.microroot-new)
/usr/lib/fs/ufs/newfs $LODEV1
mount -F ufs $LODEV1 /mnt/microroot || exit 1

# mount original microroot
echo "Mounting original microroot.."
mkdir -pv /mnt/microroot-org
LODEV2=$(lofiadm -a x86.microroot)
mount -F ufs $LODEV2 /mnt/microroot-org || exit 1

# copy original files
echo "Copying microroot contents.."
pushd /mnt/microroot-org
cp -arv . /mnt/microroot || exit 1
popd
umount $LODEV2
lofiadm -d $LODEV2

# mount root disk
echo "Copying pcfs modules.."
mkdir -pv /mnt/root
ROOTDEV=$(lofiadm -a /mnt/iso/solaris.zlib)
mount -F hsfs $ROOTDEV /mnt/root || exit 1

# copy modules
pushd /mnt/root
cp -v kernel/fs/pcfs /mnt/microroot/kernel/fs/ || exit 1
cp -rv lib/fs/pcfs /mnt/microroot/usr/lib/fs/ || exit 1
popd
umount $ROOTDEV
lofiadm -d $ROOTDEV

# apply patch
echo "Applying iso boot patch.."
pushd /mnt/microroot
patch -p0 -i $PATCH || exit 1
mkdir -p mnt/isodevice
popd

# unmount
echo "Unmounting microroot and iso.."
umount $LODEV1
lofiadm -d $LODEV1
umount $CDDEV
lofiadm -d $CDDEV

# gzip microroot
echo "Compressing microroot.."
gzip x86.microroot-new || exit 1

echo "Done."
