#!/bin/bash

# change base dir
CURDIR=$(pwd)
cd $(dirname $0)
USBROOT=$(pwd)
WORKROOT=/tmp
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

prepareiso4pmagic()
{
    local ISO=$1
    local BASEURL=$2

    if [ ! -r iso/$ISO ]; then
	if [ -n "$BASEURL" ]; then
	    mkdir -pv iso || exit 1
	    wget ${BASEURL}/${ISO}.zip -O iso/${ISO}.zip || exit 1
	    pushd iso
	    unzip -v ${ISO}.zip || exit 1
	    rm -v ${ISO}.zip
	    popd
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
    cp -v /mnt/iso/isolinux/initrd0.img $DST/initrd-${VER}.img
    umount -v /mnt/iso
    rmdir -v /mnt/iso
    # apply patch
    geninitrd $DST $VER initrd-${VER}.img $PATCH
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
    cp -v /mnt/iso/boot/isolinux/minirt.gz $DST/minirt-${VER}.gz
    umount -v /mnt/iso
    rmdir -v /mnt/iso
    # apply patch
    geninitrd $DST $VER minirt-${VER}.gz $PATCH
}

geninitrd_opensuse()
{
    local ISO=$2
    local DST=opensuse
    local PATCH=$3
    local VER=$1

    mkdir -pv /mnt/iso $DST || exit 1
    mount -v -o loop -t iso9660 iso/$ISO /mnt/iso || exit 1
    cp -v /mnt/iso/boot/i386/loader/linux $DST/linux-$VER
    cp -v /mnt/iso/boot/i386/loader/initrd $DST/initrd-${VER}
    umount -v /mnt/iso
    rmdir -v /mnt/iso
    # apply patch
    geninitrd $DST $VER initrd-${VER} $PATCH
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
    rmdir -v /mnt/iso
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
    local aftermenu
    # generate menu file
    cat cfg/head.cfg > $MENUFILE
    sort $BOOTFILE | while read line; do
	if [ -f cfg/${line}.cfg ]; then
	    aftermenu=0
	    cat cfg/${line}.cfg | while read mline; do
		if [ ! "${mline###menu}" = "${mline}" ]; then
		    aftermenu=1
		elif [ $aftermenu -eq 1 ]; then
		    echo "$mline" >> $MENUFILE
		fi
	    done
	    echo "" >> $MENUFILE
	else
	    echo "[warn] ignore ${line}"
	fi
    done
    cat cfg/tail.cfg >> $MENUFILE
    echo "Boot menu was updated."
}

installsyslinux()
{
    local USBDEV=$1
    if [ -z $USBDEV ]; then
	echo "Please specify USB device partition."
	exit 1
    fi
    if [ -z $(which syslinux) ]; then
	echo "Please install syslinux and try again."
	exit 1
    fi

    syslinux $USBDEV || exit 1
    echo "Syslinux was installed."
}

installgrub4dos()
{
    local BASEURL=http://download.gna.org/grub4dos/
    local ZIPFILE=grub4dos-0.4.4-2009-06-20.zip
    local VER=0.4.4
    local GRUBFILE=grub.exe

    if [ ! -f $GRUBFILE ]; then
	wget $BASEURL/$ZIPFILE -O $ZIPFILE || exit 1
	unzip -o $ZIPFILE grub4dos-${VER}/$GRUBFILE || exit 1
	mv -v grub4dos-${VER}/$GRUBFILE .
	rm -rv grub4dos-${VER}
	rm -v $ZIPFILE
	echo "Grub4dos was installed."
    else
	echo "Grub4dos is exist."
    fi
}

loadcfg()
{
    local CFGFILE=$1
    cat $CFGFILE | while read line; do
	if [ ! "${line###menu}" = "$line" ]; then
	    break
	else
	    eval $line || exit 1
	fi
    done
}

if [ -z "$1" ]; then
    echo "Please specify distro name."
    exit 1
fi

if [ -z $(which wget) ]; then
    echo "Please install wget first."
    exit 1
fi

DISTRO=$1

case $DISTRO in
    bootloader)
	if [ -z $(which mlabel) ]; then
	    echo "Please install mtools and try again."
	    exit 1
	fi
	if [ -z $(grep "mtools_skip_check" ~/.mtoolsrc) ]; then	
	    echo "mtools_skip_check=1" >> ~/.mtoolsrc
	fi
	mlabel -i $2 -c ::MULTIBOOT
	mlabel -i $2 -s ::
	installsyslinux $2
	installgrub4dos
	;;
    genmenu)
	genmenu
	;;
    create-casper-rw)
	if [ -f casper-rw ]; then
	    echo "casper-rw is exist."
	    exit 1
	fi
	SIZE=$2
	SIZE=${SIZE:-1024}
	dd if=/dev/zero of=casper-rw bs=1M count=$SIZE || exit 1
	mkfs.ext3 -j -F casper-rw || exit 1
	echo "casper-rw was created."
	;;

    # for development
    genpatch)
	PATCH=$2
	cd $CURDIR
	find . -name '*.org' | sed 's/\.org$//' | xargs -iF diff -c F.org F > $PATCH
	;;
    applypatch)
	PATCH=$2
	cd $CURDIR
	patch -p0 -b -z .org -i $PATCH
	;;

    *)
	CFGFILE=cfg/${DISTRO}.cfg
	if [ -f $CFGFILE ]; then
	    loadcfg $CFGFILE
	    addboot $DISTRO
	else
	    echo "$DISTRO is not supported."
	fi
	;;
esac
