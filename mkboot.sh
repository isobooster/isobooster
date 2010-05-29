#!/bin/bash

# change base dir
CURDIR=$(pwd)
cd $(dirname $0)
USBROOT=$(pwd)
WORKROOT=/tmp
MENUFILE=menu.lst
BOOTFILE=boot.lst
ISOMOUNTDIR=/mnt/iso

prepareiso()
{
    local ISO="${1}"
    local BASEURL="${2}"
    local URL

    if [ ! -r iso/$ISO -o ! -s iso/$ISO ]; then
	if [ -n "$BASEURL" ]; then
	    mkdir -pv iso || return 1
	    if [ "${BASEURL%%.iso}" = "${BASEURL}" ]; then
		URL=${BASEURL}/$ISO
	    else
		URL=${BASEURL}
	    fi
	    wget ${URL} -O iso/$ISO || return 1
	else
	    echo "$ISO is not exist."
	    return 1
	fi
    fi
}

prepareiso4pmagic()
{
    local ISO=$1
    local BASEURL=$2

    if [ ! -r iso/$ISO ]; then
	if [ -n "$BASEURL" ]; then
	    mkdir -pv iso || return 1
	    wget ${BASEURL}/${ISO}.zip -O iso/${ISO}.zip || return 1
	    pushd iso
	    unzip -v ${ISO}.zip || return 1
	    rm -v ${ISO}.zip
	    popd
	else
	    echo "$ISO is not exist."
	    return 1
	fi
    fi
}

mountiso()
{
    local ISO=$1
    if [ -d $ISOMOUNTDIR ]; then
	umountiso || return 1
    fi
    mkdir -pv $ISOMOUNTDIR || return 1
    mount -v -o loop -t iso9660 iso/$ISO $ISOMOUNTDIR || return 1
}

umountiso()
{
    umount -v $ISOMOUNTDIR || return 1
    rmdir -v $ISOMOUNTDIR || return 1
}

copyfromiso()
{
    local FROM=$1
    local DST=$2
    local ISO=$3
    if [ -z "$ISO" -a -n "$ISOFILE" ]; then
	ISO=$ISOFILE
    fi

    if [ ! -d $ISOMOUNTDIR ]; then
	mountiso $ISO || return 1
    fi

    if [ ! -d $(dirname $DST) ]; then
	mkdir -pv $(dirname $DST) || return 1
    fi

    if [ -f $ISOMOUNTDIR/$FROM ]; then
	cp -v $ISOMOUNTDIR/$FROM $DST || return 1
    elif [ -f $ISOMOUNTDIR$FROM ]; then
	cp -v $ISOMOUNTDIR$FROM $DST || return 1
    else
	echo "Fail to copy ${FROM}."
	return 1
    fi
}

geninitrd()
{
    local DST=$2
    local PATCH=$3
    local SOURCE=$1
    local WORK=$WORKROOT/initrd-work

    rm -rf $WORK
    mkdir -pv $WORK
    pushd $WORK
    zcat $USBROOT/$SOURCE | cpio -i -H newc --no-absolute-filenames
    if [ ! -f init ]; then
	echo "Fail to extract initrd."
	return 1
    fi
    patch -p0 < $USBROOT/$PATCH || return 1
    echo "Creating patched initrd"
    find . | cpio -o -H newc | gzip - > $USBROOT/$DST
    popd
    if [ ! -s $DST ]; then
	echo "Fail to generate initrd."
	return 1
    else
	echo "$INITRDMOD was generated."
    fi
    rm -rf $WORK
}

geninitrd_mount()
{
    local DST=$2
    local PATCH=$3
    local SOURCE=$1
    local SOURCEFILE=$(basename $SOURCE)
    local WORK=$WORKROOT/initrd-work
    local INITRD_MOUNT=/mnt/initrd

    rm -rf $WORK
    mkdir -pv $WORK $INITRD_MOUNT || return 1
    cp -v $USBROOT/$SOURCE $WORK || return 1
    if [ ! "${SOURCEFILE%%.gz}" = "$SOURCEFILE" ]; then
	gunzip $WORK/$SOURCEFILE || return 1
	SOURCEFILE="${SOURCEFILE%%.gz}"
    fi
    mount -o loop $WORK/$SOURCEFILE $INITRD_MOUNT || return 1
    pushd $INITRD_MOUNT
    patch -p0 < $USBROOT/$PATCH || return 1
    popd
    umount $INITRD_MOUNT || return 1
    echo "Creating patched initrd"
    gzip -c $WORK/$SOURCEFILE > $USBROOT/$DST || return 1
    if [ ! -s $DST ]; then
	echo "Fail to generate initrd."
	return 1
    else
	echo "$DST was generated."
    fi
    rm -rf $WORK $INITRD_MOUNT
}

copyiso()
{
    local ISO=$2
    local DST=$1

    if [ -d $DST ]; then
	# clean previous folder first
	rm -rv $DST
    fi
    mkdir -pv $DST || return 1
    mountiso $ISO || return 1
    cp -rv ${ISOMOUNTDIR}/* $DST
    umountiso
}

addboot()
{
    local BOOT=$1
    if [ ! -f cfg/${BOOT}.cfg ]; then
	echo "Configuration file is not found for ${BOOT}."
	return 1
    fi
    if [ ! -f $BOOTFILE ]; then
	touch $BOOTFILE || return 1
    fi
    if [ -z $(grep "$BOOT" $BOOTFILE) ]; then
	echo "$BOOT" >> $BOOTFILE
	echo "$BOOT was added to boot list."
    else
	echo "$BOOT is already installed."
    fi
    genmenu
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
	return 1
    fi
    if [ -z $(which syslinux) ]; then
	echo "Please install syslinux and try again."
	return 1
    fi

    syslinux $USBDEV || return 1
    echo "Syslinux was installed."
}

installgrub4dos()
{
    local BASEURL=http://download.gna.org/grub4dos/
    local ZIPFILE=grub4dos-0.4.4-2009-06-20.zip
    local VER=0.4.4
    local GRUBFILE=grub.exe

    if [ ! -f $GRUBFILE ]; then
	wget $BASEURL/$ZIPFILE -O $ZIPFILE || return 1
	unzip -o $ZIPFILE grub4dos-${VER}/$GRUBFILE || return 1
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
	    eval $line || return 1
	fi
    done
    return $ret
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
	mlabel -i $2 -c ::MULTIBOOT || exit 1
	mlabel -i $2 -s ::
	installsyslinux $2 || exit 1
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
	    if [ -d $ISOMOUNTDIR ]; then
		umountiso || exit 1
	    fi
	    loadcfg $CFGFILE
	    ret=$?
	    if [ -d $ISOMOUNTDIR ]; then
		umountiso || exit 1
	    fi
	    if [ $ret -ne 0 ]; then
		exit $ret
	    fi
	    addboot $DISTRO
	else
	    echo "$DISTRO is not supported."
	fi
	;;
esac
