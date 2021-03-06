#!/bin/bash

# change base dir
CURDIR=$(pwd)
cd $(dirname $0)
USBROOT=$(pwd)
WORKROOT=/tmp
MENUFILE=boot/grub/grub.cfg
MENU1FILE=boot/grub/menu.lst
BOOTFILE=boot/boot.lst
ISOMOUNTDIR=/mnt/iso
INITRD_MOUNTDIR=/mnt/initrd

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

checksum()
{
    local FILE=$1
    local SUM=$2
    local TYPE=$3
    if [ -z "$TYPE" ]; then
	TYPE="md5"
    fi

    test -z "${FILE%%/*}" && FILE="${FILE#/}"

    echo "checking $TYPE sum.."

    if [ -s ${FILE}.sum ]; then
	ORGSUM=$(cat ${FILE}.sum | cut -f 1 -d ' ')
	test "$ORGSUM" = "$SUM"
    else
	case $TYPE in
	    md5)
		echo "$SUM  $FILE" | md5sum -c
		;;
	    sha1)
		echo "$SUM  $FILE" | sha1sum -c
		;;
	    sha256)
		echo "$SUM  $FILE" | sha256sum -c
		;;
	    *)
		echo "Unknown checksum type: $TYPE"
		return 1
		;;
	esac
    fi
    if [ $? -ne 0 ]; then
	echo "$TYPE sum is not matched. Please download $FILE again."
	return 1
    else
	echo "$SUM  $FILE" > ${FILE}.sum
    fi
    echo "$TYPE sum was verified."
    return 0
}

mountiso()
{
    local ISO=$1
    if [ -d $ISOMOUNTDIR ]; then
	umountiso || return 1
    fi
    mkdir -pv $ISOMOUNTDIR || return 1
    mount -v -o loop -t iso9660 $USBROOT/iso/$ISO $ISOMOUNTDIR || return 1
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

    if [ -e $ISOMOUNTDIR/$FROM ]; then
	cp -vr $ISOMOUNTDIR/$FROM $DST || return 1
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
    local SOURCEFILE=$(basename $SOURCE)
    local SRCFORMAT=$4
    local DSTFORMAT=$5
    local WORK=$WORKROOT/initrd-work

    [ -z "$SRCFORMAT" ] && SRCFORMAT="cpio:gz"
    [ -z "$DSTFORMAT" ] && DSTFORMAT="cpio:gz"

    if [ -d $INITRD_MOUNTDIR ]; then
	umount $INITRD_MOUNTDIR || true
	rmdir -v $INITRD_MOUNTDIR || return 1
    fi

    if [ -z "${SOURCE%%@iso*}" -a -n "$ISOFILE" ]; then
	if [ ! -d $ISOMOUNTDIR ]; then
	    mountiso $ISOFILE || return 1
	fi
	SOURCE="${ISOMOUNTDIR}${SOURCE#@iso}"
    else
	SOURCE=$USBROOT/${SOURCE#/}
    fi

    rm -rf $WORK
    mkdir -pv $WORK

    case "${SRCFORMAT%:*}" in
	ext*|ufs)
	    # decompress
	    case "${SRCFORMAT#*:}" in
		gz)
		    echo "Decompressing initrd."
		    zcat -q $SOURCE > $WORK/initrd
		    [ ! -s $WORK/initrd ] && return 1
		    SOURCEFILE="initrd"
		    ;;
		lzma)
		    echo "Decompressing initrd."
		    lzcat -q -S .${SOURCEFILE##*.} $SOURCE > $WORK/initrd
		    [ ! -s $WORK/initrd ] && return 1
		    SOURCEFILE="initrd"
		    ;;
		*)
		    # just copy the file
		    cp -v $SOURCE $WORK || return 1
		    ;;
	    esac
	    echo "Mounting initrd."
	    mkdir -pv $INITRD_MOUNTDIR || return 1
	    mount -o loop -t ${SRCFORMAT%:*} $WORK/$SOURCEFILE $INITRD_MOUNTDIR || return 1
	    pushd $INITRD_MOUNTDIR
	    ;;

	cpio)
	    pushd $WORK
	    echo "Extracting initrd."
	    local CPIOOPT="-i -H newc --no-absolute-filenames"
	    case "${SRCFORMAT#*:}" in
		gz)
		    zcat -q $SOURCE | cpio $CPIOOPT || return 1
		    ;;
		lzma)
		    lzcat -q -S .${SOURCEFILE##*.} $SOURCE | cpio $CPIOOPT || return 1
		    ;;
	    esac
	    ;;

	cramfs)
	    if [ ! $(which mkcramfs) ]; then
		echo "Please install cramfsprogs package first."
		return 1
	    fi
	    mkdir -pv $INITRD_MOUNTDIR || return 1
	    mount -v -o loop -t cramfs $SOURCE $INITRD_MOUNTDIR || return 1
	    echo "Copying initrd files."
	    cp -ar ${INITRD_MOUNTDIR}/. $WORK
	    umount -v $INITRD_MOUNTDIR || return 1
	    rmdir -v $INITRD_MOUNTDIR
	    pushd $WORK
	    ;;
    esac

    patch -p0 -i $USBROOT/${PATCH#/}
    local PATCHRET=$?
    if [ $PATCHRET -ne 0 ]; then
	if [ -d $INITRD_MOUNTDIR ]; then
	    popd
	    umount -v $INITRD_MOUNTDIR || return 1
	    rmdir -v $INITRD_MOUNTDIR
	fi
	return $PATCHRET
    fi

    case "${DSTFORMAT%:*}" in
	ext*|ufs)
	    echo "Creating patched initrd."
	    popd
	    umount -v $INITRD_MOUNTDIR || return 1
	    rmdir -v $INITRD_MOUNTDIR
	    case "${DSTFORMAT#*:}" in
		gz)
		    gzip -c $WORK/$SOURCEFILE > $USBROOT/${DST#/} || return 1
		    ;;
		lzma)
		    lzma -cz $WORK/$SOURCEFILE > $USBROOT/${DST#/} || return 1
		    ;;
	    esac
	    ;;
	cpio)
	    echo "Creating patched initrd."
	    case "${DSTFORMAT#*:}" in
		gz)
		    find . | cpio --quiet -o -H newc | gzip - > $USBROOT/${DST#/}
		    ;;
		lzma)
		    find . | cpio --quiet -o -H newc | lzma -cz - > $USBROOT/${DST#/}
		    ;;
	    esac
	    popd
	    ;;
	cramfs)
	    echo "Creating patched initrd."
	    mkcramfs . $USBROOT/${DST#/} || return 1
	    popd
	    ;;
    esac
    if [ -d $INITRD_MOUNTDIR ]; then
	umount -v $INITRD_MOUNTDIR || return 1
	rmdir -v $INITRD_MOUNTDIR
    fi

    if [ ! -s $USBROOT/${DST#/} ]; then
	echo "Fail to generate initrd."
	return 1
    else
	echo "$DST was generated."
    fi
    rm -rf $WORK
}

geninitrd_lzma()
{
    geninitrd $1 $2 $3 cpio:lzma cpio:lzma
}

geninitrd_mount()
{
    local SRCFORMAT
    if [ "${1##*.}" = "gz" ]; then
	SRCFORMAT="ext2:gz"
    else
	SRCFORMAT="ext2"
    fi
    geninitrd $1 $2 $3 $SRCFORMAT ext2:gz
}

geninitrd_cramfs()
{
    geninitrd $1 $2 $3 cramfs cramfs
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
    if grep "^${BOOT}\$" $BOOTFILE >/dev/null; then
	echo "$BOOT is already installed."
    else
	echo "$BOOT" >> $BOOTFILE
	echo "$BOOT was added to boot list."
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
    local grubver
    # generate menu file
    echo -n "Generating boot menu."
    cat cfg/head.cfg > $MENUFILE
    cat cfg/head1.cfg > $MENU1FILE
    sort $BOOTFILE | while read line; do
	if [ -f cfg/${line}.cfg ]; then
	    local aftermenu=0
	    local global=1
	    cat cfg/${line}.cfg | while read mline; do
		test -z "$mline" && continue
		case $mline in
		    "#menu"*)
			aftermenu=1
			if [ -z "${mline%%#menu1*}" ]; then
			    grubver=1
			else
			    grubver=2
			fi
			global=0
			;;
		    "#install"*|"#remove"*|"#command"*)
			aftermenu=0
			global=0
			;;
		    *)
			if [ $aftermenu -eq 1 ]; then
			    case $grubver in
				1)
				    eval "echo \"$mline\"" >> $MENU1FILE
				    ;;
				*)
		    # replace " -> @, because eval removes "
				    mline=$(echo $mline | sed 's/\"/@/g')
				    mline=$(eval "echo \"$mline\"")
		    # replace back @ -> "
				    mline=$(echo $mline | sed 's/@/\"/g')
				    echo "$mline" >> $MENUFILE
				    ;;
			    esac
			elif [ $global -eq 1 ]; then
			    eval $mline
			fi
			;;
		esac
	    done
	    echo "" >> $MENUFILE
	    echo -n "."
	else
	    echo -n "[warn] ignore ${line}"
	fi
    done
    cat cfg/tail.cfg >> $MENUFILE
    cat cfg/tail1.cfg >> $MENU1FILE
    echo ""
    echo "Boot menu was updated."
}

# we don't need syslinux now.

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

# for chainload from grub2

installgrub4dos()
{
    local BASEURL=http://download.gna.org/grub4dos/
    local ZIPFILE=grub4dos-0.4.4-2009-06-20.zip
    local VER=0.4.4
    local GRUBFILE=grub.exe
    local DEFAULTFILE=default

    if [ ! -f $GRUBFILE -o ! -f $DEFAULTFILE ]; then
	wget $BASEURL/$ZIPFILE -O $ZIPFILE || return 1
	unzip -o $ZIPFILE grub4dos-${VER}/$GRUBFILE grub4dos-${VER}/$DEFAULTFILE || return 1
	mv -v grub4dos-${VER}/$GRUBFILE .
	mv -v grub4dos-${VER}/$DEFAULTFILE .
	rm -rv grub4dos-${VER}
	rm -v $ZIPFILE
	echo "Grub4dos was installed."
    else
	echo "Grub4dos is exist."
    fi
}

installgrub2()
{
    local USBDEV=$1
    if [ -z $USBDEV ]; then
	echo "Please specify USB device."
	return 1
    fi
    if [ -z $(which grub-install) ]; then
	echo "Please install grub2 and try again."
	return 1
    fi

    grub-install --no-floppy --root-directory=${USBROOT} --force $USBDEV || return 1
    grub-set-default --root-directory=${USBROOT} 0
    local BASEFONT=/usr/share/fonts/X11/misc/7x14.pcf.gz
    local DISTFONT=${USBROOT}/boot/themes/menufont.pf2
    if [ -f $BASEFONT ]; then
	grub-mkfont --output=$DISTFONT $BASEFONT
    fi

    echo "Grub2 was installed."
}

installcfg()
{
    local CFGFILE=$1
    local afterinstall=1
    cat $CFGFILE | while read line; do
	test -z "$line" && continue
	case $line in
	    "#install"*)
		afterinstall=1
		;;
	    "#menu"*|"#remove"*|"#command"*)
		afterinstall=0
		;;
	    *)
		if [ $afterinstall -eq 1 ]; then
		    eval $line || return 1
		fi
		;;
	esac
    done
    return $?
}

removecfg()
{
    local CFGFILE=$1
    local flag=$2
    local afterremove=1
    cat $CFGFILE | while read line; do
	test -z "$line" && continue
	case $line in
	    "#remove"*)
		afterremove=1
		;;
	    "#menu"*|"#install"*|"#command"*)
		afterremove=0
		;;
	    *)
		if [ $afterremove -eq 1 ]; then
		    if [ "$flag" = "purge" -o -n "${line%%purgefile*}" ]; then
			eval $line || return 1
		    fi
		fi
		;;
	esac
    done
    return $?
}

commandcfg()
{
    local CFGFILE=$1
    shift
    local COMMAND=$1
    shift
    local aftercommand=1
    local ARGS="$@"
    cat $CFGFILE | while read line; do
	test -z "$line" && continue
	case $line in
	    '#command'*)
		if [ "${line#'#command '}" = "$COMMAND" ]; then
		    aftercommand=1
		else
		    aftercommand=0
		fi
		;;
	    '#menu'*|'#remove'*|'#install'*)
		aftercommand=0
		;;
	    *)
		if [ $aftercommand -eq 1 ]; then
		    eval $line || return 1
		fi
		;;
	esac
    done
    return $?
}

rmfile()
{
    local file=$1
    # remove first /
    test -z "${file%%/*}" && file="${file#/}"

    test -e $file && rm -rfv $file
    test -e ${file}.sum && rm -rfv ${file}.sum
    return 0
}

purgefile()
{
    local file=$1
    # remove first /
    test -z "${file%%/*}" && file="${file#/}"

    test -e $file && rm -rfv $file
    test -e ${file}.sum && rm -rfv ${file}.sum
    return 0
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
	DEV=$2
	if [ -z $(which mlabel) ]; then
	    echo "Please install mtools and try again."
	    exit 1
	fi
	if [ -z $(grep "mtools_skip_check" ~/.mtoolsrc) ]; then	
	    echo "mtools_skip_check=1" >> ~/.mtoolsrc
	fi
	mlabel -i ${DEV}1 -c ::MULTIBOOT || exit 1
	mlabel -i ${DEV}1 -s ::
#	installsyslinux ${DEV}1 || exit 1
	installgrub4dos
	installgrub2 $DEV
	;;

    genmenu)
	genmenu
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
	    elif [ -z "$ARG" ]; then
		installcfg $CFGFILE
	    else
		shift
		shift
		commandcfg $CFGFILE $ARG $*
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
	    elif [ -z "$ARG" ]; then
		addboot $DISTRO
	    fi
	else
	    echo "$DISTRO is not supported."
	fi
	;;
esac
