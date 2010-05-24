#!/bin/sh

cd `dirname $0`

copyiso()
{
    ISO=$1
    DST=$2

    if [ -d $DST ]; then
	# clean previous folder first
	rm -rv $DST
    fi
    mkdir -pv /mnt/iso $DST || exit 1
    mount -v -o loop $ISO /mnt/iso || exit 1
    cp -rv /mnt/iso/* $DST
    umount -v /mnt/iso
    rmdir /mnt/iso
}

copyknoppix()
{
    ISO=$1
    DST=KNOPPIX

    if [ -d $DST ]; then
	# clean previous folder first
	rm -rv $DST
    fi
    mkdir -pv /mnt/iso $DST || exit 1
    mount -v -o loop $ISO /mnt/iso || exit 1
    cp -rv /mnt/iso/KNOPPIX/* $DST
    cp -rv /mnt/iso/boot $DST
    umount -v /mnt/iso
    rmdir /mnt/iso
}

if [ -z "$1" ]; then
    echo "Please specify distro name."
    exit 1
fi

case $1 in
    fedora-12)
	ISO=iso/Fedora-12-i686-Live.iso
	copyiso $ISO $1
	;;
    soas2)
	ISO=iso/soas-2-blueberry.iso
	copyiso $ISO $1
	;;
    knoppix)
	ISO=iso/knoppix_v6.0.1CD_20090208-20090225_opt.iso
	copyknoppix $ISO
	;;
    rescue)
	ISO=iso/systemrescuecd-x86-1.5.4.iso
	copyiso $ISO $1
	;;
esac
