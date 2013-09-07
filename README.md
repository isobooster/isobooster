isobooster
==========

isobooster - Multiboot USB tool is the script to create multiboot USB stick
that uses ISO files to boot each LiveOS directly.
You can easily install and remove each OS and install huge number of LiveOS in one USB stick.

Please see the official site for details.

* <http://multiboot-usb.yoshimov.com/>

## Install

### 1. Create VFAT(FAT32) partition.

You should create standard USB stick with VFAT format.

You can use GParted or Windows Explorer to create it.

### 2. Prepare files.

Download multiboot scripts from GitHub using git command like this:

    sudo aptitude install bzr mtools wget
    cd /media/<somewhere>
    git init
    git pull https://github.com/isobooster/isobooster.git

Or, you could download tar.gz file from Download page.
You should extract whole files into the root folder of USB stick like this:

    cd /media/<somewhere>
    tar zxvf isobooster-xxxx.tar.gz

### 3. Install bootloader.

You could install bootloader like this:

    sudo bash mkboot.sh bootloader /dev/sdb

You should specify device name in argument. Not partition. And the first partition should be vfat (fat32).

This command install the grub2 and grub4dos, and also change the label of USB stick.

### 4. Install each OS.

Finally, you could install each OS using following command:

    sudo bash mkboot.sh ubuntu-10.04
    sudo bash mkboot.sh centos-5.5

You can specify os name same as the cfg files in the cfg/ folder.
This command will download ISO file and generate patched initrd file, and configuration file for grub.

### 5. Boot the LiveOS!

And then, you could boot the installed LiveOS from USB stick.
