#!/bin/bash

# change base dir
cd `dirname $0`

WORKROOT=/tmp
USBROOT=$(pwd)
MENUFILE=menu.lst
BOOTFILE=boot.lst

prepareiso()
{
    local ISO=$1
    local BASEURL=$2

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

geninitrd()
{
    local DST=$1
    local VER=$2
    local PATCH=$4
    local SOURCE=$3
    local WORK=$WORKROOT/cpio-work

    rm -rf $WORK
    mkdir -pv $WORK
    pushd $WORK
    zcat $USBROOT/$DST/$SOURCE | cpio -i -H newc --no-absolute-filenames
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
}

geninitrd_centos()
{
    # for CentOS and Fedora
    local ISO=$3
    local DST=$1
    local PATCH=$4
    local VER=$2

    mkdir -pv /mnt/iso $DST || exit 1
    mount -v -o loop -t iso9660 iso/$ISO /mnt/iso || exit 1
    cp -v /mnt/iso/isolinux/vmlinuz0 $DST/vmlinuz-$VER
    cp -v /mnt/iso/isolinux/initrd0.img $DST
    umount -v /mnt/iso
    rmdir /mnt/iso
    # apply patch
    geninitrd $DST $VER initrd0.img $PATCH
    rm $DST/initrd0.img
}

geninitrd_knoppix()
{
    local ISO=$2
    local DST=knoppix
    local PATCH=$3
    local VER=$1

    mkdir -pv /mnt/iso $DST || exit 1
    mount -v -o loop -t iso9660 iso/$ISO /mnt/iso || exit 1
    cp -v /mnt/iso/boot/isolinux/linux $DST/linux-$VER
    cp -v /mnt/iso/boot/isolinux/minirt.gz $DST
    umount -v /mnt/iso
    rmdir /mnt/iso
    # apply patch
    geninitrd $DST $VER minirt.gz $PATCH
    rm $DST/minirt.gz
}

copyiso()
{
    local ISO=$2
    local DST=$1

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

addboot()
{
    local BOOT=$1
    if [ ! -f cfg/${BOOT}.cfg ]; then
	echo "Configuration file is not found for ${BOOT}."
	exit 1
    fi
    if [ ! -f $BOOTFILE ]; then
	touch $BOOTFILE || exit 1
    fi
    if [ -z $(grep "$BOOT" $BOOTFILE) ]; then
	echo "$BOOT" >> $BOOTFILE
	echo "$BOOT was added to boot list."
	genmenu
    else
	echo "$BOOT is already installed."
    fi
}

genmenu()
{
    # sort the order
    sort $BOOTFILE > ${BOOTFILE}.new
    mv -fv ${BOOTFILE}.new ${BOOTFILE}
    # generate menu file
    cat cfg/head.cfg > $MENUFILE
    while read line; do
	cat cfg/${line}.cfg >> $MENUFILE
	echo "" >> $MENUFILE
    done < $BOOTFILE
    cat cfg/tail.cfg >> $MENUFILE
    echo "New menu was generated."
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
    genmenu)
	genmenu
	;;
    ubuntu-8.04)
	ISOFILE=ubuntu-8.04.4-desktop-i386.iso
	BASEURL=http://releases.ubuntu.com/8.04.4
	prepareiso $ISOFILE $BASEURL
	addboot ubuntu-8.04
	;;
    ubuntu-9.04)
	ISOFILE=ubuntu-9.04-desktop-i386.iso
	BASEURL=http://releases.ubuntu.com/9.04
	prepareiso $ISOFILE $BASEURL
	addboot ubuntu-9.04
	;;
    ubuntu-9.10)
	ISOFILE=ubuntu-9.10-desktop-i386.iso
	BASEURL=http://releases.ubuntu.com/9.10
	prepareiso $ISOFILE $BASEURL
	addboot ubuntu-9.10
	;;
    ubuntu-10.04)
	ISOFILE=ubuntu-10.04-desktop-i386.iso
	BASEURL=http://releases.ubuntu.com/10.04
	prepareiso $ISOFILE $BASEURL
	addboot ubuntu-10.04
	;;
    mint-9)
	ISOFILE=linuxmint-9-gnome-cd-i386.iso
	BASEURL=http://mirror.amarillolinux.com/linuxmint/stable/9
	prepareiso $ISOFILE $BASEURL
	addboot mint-9
	;;
    dsl|dsl-4.4.10)
	ISOFILE=dsl-4.4.10-initrd.iso
	BASEURL=http://distro.ibiblio.org/pub/linux/distributions/damnsmall/current
	prepareiso $ISOFILE $BASEURL
	addboot dsl-4.4.10
	;;
    netbootcd|netbootcd-3.2.1)
	ISOFILE=NetbootCD-3.2.1.iso
	BASEURL=http://downloads.tuxfamily.org/netbootcd/3.2.1
	prepareiso $ISOFILE $BASEURL
	addboot netbootcd-3.2.1
	;;
    fedora-12)
	ISOFILE=Fedora-12-i686-Live.iso
	BASEURL=http://download.fedoraproject.org/pub/fedora/linux/releases/12/Live/i686
	prepareiso $ISOFILE $BASEURL
	geninitrd_centos fedora 12 $ISOFILE fedora/fedora-12.patch
	addboot fedora-12
	;;
    soas2)
	ISOFILE=soas-2-blueberry.iso
	BASEURL=http://download.sugarlabs.org/soas/releases
	prepareiso $ISOFILE $BASEURL
	copyiso soas2 $ISOFILE
	addboot soas2
	;;
    knoppix-jp|knoppix-6.0.1-jp)
	# japanese version
	ISOFILE=knoppix_v6.0.1CD_20090208-20090225_opt.iso
	BASEURL=http://ring.aist.go.jp/pub/linux/knoppix/iso
	prepareiso $ISOFILE $BASEURL
	geninitrd_knoppix 6.0.1-jp $ISOFILE knoppix/knoppix-6.0.1-jp.patch
	addboot knoppix-6.0.1-jp
	;;
    knoppix-6.2.1)
	ISOFILE=KNOPPIX_V6.2.1CD-2010-01-31-EN.iso 
	BASEURL=http://ftp.knoppix.nl/os/Linux/distr/knoppix
	prepareiso $ISOFILE $BASEURL
	geninitrd_knoppix 6.2.1 $ISOFILE knoppix/knoppix-6.0.1-jp.patch
	addboot knoppix-6.2.1
	;;
    rescue|rescue-1.5.4)
	ISOFILE=systemrescuecd-x86-1.5.4.iso
	BASEURL=http://downloads.sourceforge.net/project/systemrescuecd/sysresccd-x86/1.5.4
	prepareiso $ISOFILE $BASEURL
	copyiso rescue-1.5.4 $ISOFILE
	addboot systemrescuecd-1.5.4
	;;
    centos-5|centos-5.5)
	ISOFILE=CentOS-5.5-i386-LiveCD.iso
	BASEURL=http://ftp.osuosl.org/pub/centos/5.5/isos/i386
	prepareiso $ISOFILE $BASEURL
	geninitrd_centos centos 5.5 $ISOFILE centos/centos-5.5.patch
	addboot centos-5.5
	;;
    opensuse-11|opensuse-11.2)
	ISOFILE=openSUSE-11.2-GNOME-LiveCD-i686.iso
	BASEURL=http://download.opensuse.org/distribution/11.2/iso
	prepareiso $ISOFILE $BASEURL
	copyiso opensuse-11.2 $ISOFILE
	addboot opensuse-11.2
	;;
    puppy-5|puppy-5.00)
	ISOFILE=lupu-500.iso
	BASEURL=http://distro.ibiblio.org/pub/linux/distributions/puppylinux/puppy-5.0
	prepareiso $ISOFILE $BASEURL
	copyiso puppy-5.00 $ISOFILE
	addboot puppy-5.00
	;;
    *)
	echo "$DISTRO is not supported."
	;;
esac
