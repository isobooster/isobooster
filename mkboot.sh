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
    local ISO=$1
    local BASEURL=$2

    if [ ! -r iso/$ISO -o ! -s iso/$ISO ]; then
	if [ -n "$BASEURL" ]; then
	    mkdir -pv iso || return 1
	    wget -c ${BASEURL} -O iso/${ISO}.part || return 1
	    mv -v iso/${ISO}.part iso/$ISO || return 1
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
    umount -v $ISOMOUNTDIR || true
    rmdir -v $ISOMOUNTDIR || return 1
}

copyfromiso()
{
    local FROM=$1
    local DST=$2
    local ISO=$3

    test -z "$ISO" -a -n "$ISOFILE" && ISO=$ISOFILE
    # remove first /
    test -z "${FROM%%/*}" && FROM="${FROM#/}"
    test -z "${DST%%/*}" && DST="${DST#/}"

    if [ ! -d $ISOMOUNTDIR ]; then
	mountiso $ISO || return 1
    fi

    if [ ! -d $(dirname $DST) ]; then
	mkdir -pv $(dirname $DST) || return 1
    fi

    if [ -f $ISOMOUNTDIR/$FROM ]; then
	cp -v $ISOMOUNTDIR/$FROM $DST || return 1
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

    # remove first /
    test -z "${DST%%/*}" && DST="${DST#/}"
    test -z "${PATCH%%/*}" && PATCH="${PATCH#/}"
    test -z "${SOURCE%%/*}" && SOURCE="${SOURCE#/}"

    rm -rf $WORK
    mkdir -pv $WORK
    pushd $WORK
    zcat $USBROOT/$SOURCE | cpio -i -H newc --no-absolute-filenames
    if [ ! -f init ]; then
	echo "Fail to extract initrd."
	return 1
    fi
    patch -p0 -i $USBROOT/$PATCH || return 1
    echo "Creating patched initrd"
    find . | cpio -o -H newc | gzip - > $USBROOT/$DST
    popd
    if [ ! -s $DST ]; then
	echo "Fail to generate initrd."
	return 1
    else
	echo "$DST was generated."
    fi
    rm -rf $WORK
}

geninitrd_mount()
{
    local DST=$2
    local PATCH=$3
    local SOURCE=$1
    local WORK=$WORKROOT/initrd-work
    local INITRD_MOUNT=/mnt/initrd

    # remove first /
    test -z "${DST%%/*}" && DST="${DST#/}"
    test -z "${PATCH%%/*}" && PATCH="${PATCH#/}"
    test -z "${SOURCE%%/*}" && SOURCE="${SOURCE#/}"
    local SOURCEFILE=$(basename $SOURCE)

    rm -rf $WORK
    mkdir -pv $WORK $INITRD_MOUNT || return 1
    cp -v $USBROOT/$SOURCE $WORK || return 1
    if [ ! "${SOURCEFILE%%.gz}" = "$SOURCEFILE" ]; then
	gunzip $WORK/$SOURCEFILE || return 1
	SOURCEFILE="${SOURCEFILE%%.gz}"
    fi
    mount -o loop $WORK/$SOURCEFILE $INITRD_MOUNT || return 1
    pushd $INITRD_MOUNT
    patch -p0 -i $USBROOT/$PATCH || return 1
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

geninitrd_cramfs()
{
    local DST=$2
    local PATCH=$3
    local SOURCE=$1
    local WORK=$WORKROOT/initrd-work
    local INITRD_MOUNT=/mnt/initrd

    if [ -z $(which mkcramfs) ]; then
	echo "Please install cramfsprogs package first."
	return 1
    fi

    # remove first /
    test -z "${DST%%/*}" && DST="${DST#/}"
    test -z "${PATCH%%/*}" && PATCH="${PATCH#/}"
    test -z "${SOURCE%%/*}" && SOURCE="${SOURCE#/}"
    local SOURCEFILE=$(basename $SOURCE)

    rm -rf $WORK
    mkdir -pv $WORK $INITRD_MOUNT || return 1
    mount -o loop -t cramfs $USBROOT/$SOURCE $INITRD_MOUNT || return 1
    echo "Copying initrd files."
    cp -ar ${INITRD_MOUNT}/* $WORK
    umount $INITRD_MOUNT || return 1
    pushd $WORK
    patch -p0 -i $USBROOT/$PATCH || return 1
    echo "Creating patched initrd."
    mkcramfs . $USBROOT/$DST || return 1
    popd
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
    # remove first /
    test -z "${DST%%/*}" && DST="${DST#/}"

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
    if [ -z $(grep "${BOOT}\$" $BOOTFILE) ]; then
	echo "$BOOT" >> $BOOTFILE
	echo "$BOOT was added to boot list."
    else
	echo "$BOOT is already installed."
    fi
    genmenu
}

delboot()
{
    local BOOT=$1
    if [ ! -f cfg/${BOOT}.cfg ]; then
	echo "Configuration file is not found for ${BOOT}."
	return 1
    fi
    if [ ! -f $BOOTFILE ]; then
	touch $BOOTFILE || return 1
    fi
    if [ -z $(grep "${BOOT}\$" $BOOTFILE) ]; then
	echo "$BOOT is not exist."
    else
	grep -v "${BOOT}\$" $BOOTFILE > ${BOOTFILE}.new
	mv -v ${BOOTFILE}.new $BOOTFILE
	echo "$BOOT was deleted."
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
	    local aftermenu=0
	    local global=1
	    cat cfg/${line}.cfg | while read mline; do
		test -z "$mline" && continue
		if [ -z "${mline%%#menu*}" ]; then
		    aftermenu=1
		    global=0
		elif [ -z "${mline%%#install*}" -o -z "${mline%%#remove*}" ]; then
		    aftermenu=0
		    global=0
		elif [ $aftermenu -eq 1 ]; then
		    eval "echo \"$mline\"" >> $MENUFILE
		elif [ $global -eq 1 ]; then
		    eval $mline
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
    local DEFAULTFILE=default

    if [ ! -f $GRUBFILE ]; then
	wget $BASEURL/$ZIPFILE -O $ZIPFILE || return 1
	unzip -o $ZIPFILE grub4dos-${VER}/$GRUBFILE || return 1
	mv -v grub4dos-${VER}/$GRUBFILE .
	mv -v grub4dos-${VER}/$DEFAULTFILE .
	rm -rv grub4dos-${VER}
	rm -v $ZIPFILE
	echo "Grub4dos was installed."
    else
	echo "Grub4dos is exist."
    fi
}

installcfg()
{
    local CFGFILE=$1
    local afterinstall=1
    cat $CFGFILE | while read line; do
	test -z "$line" && continue
	if [ -z "${line%%#install*}" ]; then
	    afterinstall=1
	elif [ -z "${line%%#menu*}" -o -z "${line%%#remove*}" ]; then
	    afterinstall=0
	elif [ $afterinstall -eq 1 ]; then
	    eval $line || return 1
	fi
    done
    return 0
}

removecfg()
{
    local CFGFILE=$1
    local flag=$2
    local afterremove=1
    cat $CFGFILE | while read line; do
	test -z "$line" && continue
	if [ -z "${line%%#remove*}" ]; then
	    afterremove=1
	elif [ -z "${line%%#menu*}" -o -z "${line%%#install*}" ]; then
	    afterremove=0
	elif [ $afterremove -eq 1 ]; then
	    if [ "$flag" = "purge" -o -n "${line%%purgefile*}" ]; then
		eval $line || return 1
	    fi
	fi
    done
    return 0
}

rmfile()
{
    local file=$1
    # remove first /
    test -z "${file%%/*}" && file="${file#/}"

    rm -rfv $file
}

purgefile()
{
    local file=$1
    # remove first /
    test -z "${file%%/*}" && file="${file#/}"

    rm -rfv $file
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
	ARG=$2
	if [ -f $CFGFILE ]; then
	    if [ -d $ISOMOUNTDIR ]; then
		umountiso || exit 1
	    fi
	    if [ "$ARG" = "remove" -o "$ARG" = "purge" ]; then
		removecfg $CFGFILE $ARG
	    else
		installcfg $CFGFILE
	    fi
	    ret=$?
	    if [ -d $ISOMOUNTDIR ]; then
		umountiso || exit 1
	    fi
	    if [ $ret -ne 0 ]; then
		exit $ret
	    fi
	    if [ "$ARG" = "remove" -o "$ARG" = "purge" ]; then
		delboot $DISTRO
	    else
		addboot $DISTRO
	    fi
	else
	    echo "$DISTRO is not supported."
	fi
	;;
esac
