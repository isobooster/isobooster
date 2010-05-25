#!/bin/sh

# change base dir
cd `dirname $0`

prepareiso()
{
    ISO=$1
    BASEURL=$2

    if [ ! -f iso/$ISO ]; then
	if [ -n "$BASEURL" ]; then
	    wget ${BASEURL}/$ISO -O iso/$ISO || exit 1
	else
	    echo "$ISO is not exist."
	    exit 1
	fi
    fi
}

copyiso()
{
    ISO=$2
    DST=$1
    BASEURL=$3

    prepareiso $ISO $BASEURL

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
    BASEURL=$3

    prepareiso $ISO $BASEURL

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
	copyiso $DISTRO $ISOFILE $BASEURL
	;;
    soas2)
	ISOFILE=soas-2-blueberry.iso
	BASEURL=http://download.sugarlabs.org/soas/releases
	copyiso $DISTRO $ISOFILE $BASEURL
	;;
    knoppix-jp)
	# japanese version
	ISOFILE=knoppix_v6.0.1CD_20090208-20090225_opt.iso
	BASEURL=http://ring.aist.go.jp/pub/linux/knoppix/iso
	copyknoppix knoppix-6.0.1-jp $ISOFILE $BASEURL
	;;
    rescue)
	ISOFILE=systemrescuecd-x86-1.5.4.iso
	BASEURL=http://downloads.sourceforge.net/project/systemrescuecd/sysresccd-x86/1.5.4
	copyiso $DISTRO $ISOFILE $BASEURL
	;;
    centos-5)
	ISOFILE=CentOS-5.5-i386-LiveCD.iso
	BASEURL=http://ftp.osuosl.org/pub/centos/5.5/isos/i386
	copyiso centos-5.5 $ISOFILE $BASEURL
	mv centos-5.5/LiveOS .
	;;
    opensuse-11)
	ISOFILE=openSUSE-11.2-GNOME-LiveCD-i686.iso
	BASEURL=http://download.opensuse.org/distribution/11.2/iso
	copyiso opensuse-11.2 $ISOFILE $BASEURL
	;;
    puppy-5)
	ISOFILE=lupu-500.iso
	BASEURL=http://distro.ibiblio.org/pub/linux/distributions/puppylinux/puppy-5.0
	prepareiso $ISOFILE $BASEURL
	;;
esac
