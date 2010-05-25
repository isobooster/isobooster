#!/bin/bash

# change base dir
cd `dirname $0`

WORKROOT=/tmp
USBROOT=$(pwd)

prepareiso()
{
    ISO=$1
    BASEURL=$2

    if [ ! -r iso/$ISO ]; then
	if [ -n "$BASEURL" ]; then
	    mkdir -pv iso || exit 1
	    wget ${BASEURL}/$ISO -O iso/$ISO || exit 1
	else
	    echo "$ISO is not exist."
	    exit 1
	fi
    fi
}

geninitrd_centos()
{
    ISO=$3
    DST=$1
    PATCH=$4
    VER=$2

    mkdir -pv /mnt/iso $DST || exit 1
    mount -v -o loop -t iso9660 iso/$ISO /mnt/iso || exit 1
    cp -v /mnt/iso/isolinux/vmlinuz0 $DST/vmlinuz-$VER
    cp -v /mnt/iso/isolinux/initrd0.img $DST
    umount -v /mnt/iso
    rmdir /mnt/iso
    # apply patch
    WORK=$WORKROOT/centos-cpio
    mkdir -pv $WORK
    pushd $WORK
    zcat $USBROOT/$DST/initrd0.img | cpio -i -H newc --no-absolute-filenames
    if [ ! -f init ]; then
	echo "Fail to extract initrd."
	exit 1
    fi
    patch -p0 < $USBROOT/$PATCH || exit 1
    echo "Creating patched initrd"
    find . | cpio -o -H newc | gzip - > $USBROOT/$DST/initrd-mod-${VER}.gz
    popd
    if [ ! -s $DST/initrd-mod-${VER}.gz ]; then
	echo "Fail to generate initrd."
	exit 1
    fi
    rm -rf $WORK
    rm $DST/initrd0.img
}

copyiso()
{
    ISO=$2
    DST=$1

    if [ -d $DST ]; then
	# clean previous folder first
	rm -rv $DST
    fi
    mkdir -pv /mnt/iso $DST || exit 1
    mount -v -o loop iso/$ISO /mnt/iso || exit 1
    cp -rv /mnt/iso/* $DST
    umount -v /mnt/iso
    rmdir /mnt/iso
}

copyknoppix()
{
    ISO=$2
    DST=$1

    if [ -d $DST ]; then
	# clean previous folder first
	rm -rv $DST
    fi
    mkdir -pv /mnt/iso $DST || exit 1
    mount -v -o loop iso/$ISO /mnt/iso || exit 1
    cp -rv /mnt/iso/KNOPPIX/* $DST
    cp -rv /mnt/iso/boot $DST
    umount -v /mnt/iso
    rmdir /mnt/iso
}

if [ -z "$1" ]; then
    echo "Please specify distro name."
    exit 1
fi

if [ -z `which wget` ]; then
    echo "Please install wget first."
    exit 1
fi

DISTRO=$1

case $DISTRO in
    ubuntu-8.04)
	ISOFILE=ubuntu-8.04.4-desktop-i386.iso
	BASEURL=http://releases.ubuntu.com/8.04.4
	prepareiso $ISOFILE $BASEURL
	;;
    ubuntu-9.04)
	ISOFILE=ubuntu-9.04-desktop-i386.iso
	BASEURL=http://releases.ubuntu.com/9.04
	prepareiso $ISOFILE $BASEURL
	;;
    ubuntu-9.10)
	ISOFILE=ubuntu-9.10-desktop-i386.iso
	BASEURL=http://releases.ubuntu.com/9.10
	prepareiso $ISOFILE $BASEURL
	;;
    ubuntu-10.04)
	ISOFILE=ubuntu-10.04-desktop-i386.iso
	BASEURL=http://releases.ubuntu.com/10.04
	prepareiso $ISOFILE $BASEURL
	;;
    mint-9)
	ISOFILE=linuxmint-9-gnome-cd-i386.iso
	BASEURL=http://mirror.amarillolinux.com/linuxmint/stable/9
	prepareiso $ISOFILE $BASEURL
	;;
    dsl)
	ISOFILE=dsl-4.4.10-initrd.iso
	BASEURL=http://distro.ibiblio.org/pub/linux/distributions/damnsmall/current
	prepareiso $ISOFILE $BASEURL
	;;
    netbootcd)
	ISOFILE=NetbootCD-3.2.1.iso
	BASEURL=http://downloads.tuxfamily.org/netbootcd/3.2.1
	prepareiso $ISOFILE $BASEURL
	;;
    fedora-12)
	ISOFILE=Fedora-12-i686-Live.iso
	BASEURL=http://download.fedoraproject.org/pub/fedora/linux/releases/12/Live/i686
	prepareiso $ISOFILE $BASEURL
	copyiso $DISTRO $ISOFILE
	;;
    soas2)
	ISOFILE=soas-2-blueberry.iso
	BASEURL=http://download.sugarlabs.org/soas/releases
	prepareiso $ISOFILE $BASEURL
	copyiso $DISTRO $ISOFILE
	;;
    knoppix-jp)
	# japanese version
	ISOFILE=knoppix_v6.0.1CD_20090208-20090225_opt.iso
	BASEURL=http://ring.aist.go.jp/pub/linux/knoppix/iso
	prepareiso $ISOFILE $BASEURL
	copyknoppix knoppix-6.0.1-jp $ISOFILE
	;;
    rescue)
	ISOFILE=systemrescuecd-x86-1.5.4.iso
	BASEURL=http://downloads.sourceforge.net/project/systemrescuecd/sysresccd-x86/1.5.4
	prepareiso $ISOFILE $BASEURL
	copyiso $DISTRO $ISOFILE
	;;
    centos-5)
	ISOFILE=CentOS-5.5-i386-LiveCD.iso
	BASEURL=http://ftp.osuosl.org/pub/centos/5.5/isos/i386
	prepareiso $ISOFILE $BASEURL
	geninitrd_centos centos 5.5 $ISOFILE centos/centos-5.5-init.patch
	;;
    opensuse-11)
	ISOFILE=openSUSE-11.2-GNOME-LiveCD-i686.iso
	BASEURL=http://download.opensuse.org/distribution/11.2/iso
	prepareiso $ISOFILE $BASEURL
	copyiso opensuse-11.2 $ISOFILE
	;;
    puppy-5)
	ISOFILE=lupu-500.iso
	BASEURL=http://distro.ibiblio.org/pub/linux/distributions/puppylinux/puppy-5.0
	prepareiso $ISOFILE $BASEURL
	;;
esac
