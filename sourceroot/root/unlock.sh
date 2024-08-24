#!/bin/sh
#
# open all luks-encrypted devices in preparation for booting a rootfs
#
# This function is intended to run in an initrd environment and has
# been scripted specifically for the Gentoo genkernel initramfs
# overlay so it can be called from a dropbear ssh session to unlock
# devices for inclusion in a rootfs file system. This can be used
# to unlock many drives remotely for inclusion in a zfs-over-luks
# rootfs setup.
#
# Be sure genkernel.conf includes
# INITRAMFS_OVERLAY="/etc/XXXX"
#
# Be sure the following binaries are included in your initrd
# blkid
# nvme
#

# VARS
PREFIX="sn-"    # will be added here /dev/mapper/PREFIXserial

# color management
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
ENDCOLOR="\e[0m"

#######################################
# determine the serial number of a given nvme drive
# Globals:
#   none
# Arguments:
#   device - examples: /dev/nvme0n1
# Outputs:
#   serial number of the device
# Returns:
#   0 ... always :(
#######################################
function nvme_sn() {
  local DEV="$1"
  local SN="$(nvme id-ctrl $DEV | grep '^sn ' | sed -e 's/.*: //' | xargs)"
  echo "$SN"

  return 0
}

#######################################
# determine the manufacturer of a given nvme drive
# Globals:
#   none
# Arguments:
#   device - examples: /dev/nvme0n1
# Outputs:
#   manufacturer of the device
# Returns:
#   0 ... always :(
#######################################
function nvme_manufacturer() {
  local DEV="$1"
  local MAN="$(nvme id-ctrl $DEV | grep '^mn ' | sed -e 's/.*: //' | xargs)"
  echo "$MAN"

  return 0
}

#######################################
# Call luksOpen for any type of drive
# Globals:
#   PREFIX
# Arguments:
#   device - examples: /dev/nvme0n1
#   serial number - device serial number
# Outputs:
#   text
# Returns:
#   0 success
#   1 failed
#######################################
function common_luksOpen() {
  local _dev=$1
  local _sn=$2

  local _name="$PREFIX$_sn"

  # luksOpen here
  if cryptsetup luksOpen $_dev --key-file /dev/mapper/key $_name; then
    echo -ne "${YELLOW}/dev/mapper/$_name  ${GREEN}SUCCESS${ENDCOLOR}\n"
    return 0
  else
    echo -ne "${YELLOW}/dev/mapper/$_name  ${RED}FAILED${ENDCOLOR}\n"
    return 1
  fi
}

#######################################
# Open a luks-encrypted nvme device
# Globals:
#   none
# Arguments:
#   device - examples: /dev/nvme0n1
# Outputs:
#   text
# Returns:
#   0 ... always :(
#######################################
function process_nvme() {
  local _dev=$1

  local _sn=$(nvme_sn $_dev)
  local _man=$(nvme_manufacturer $_dev)

  echo -ne "${YELLOW}$_man  $_sn  ${ENDCOLOR}"
  common_luksOpen $_dev $_sn
  return 0

}

#######################################
# Open a luks-encrypted sata device
# Globals:
#   none
# Arguments:
#   device - examples: /dev/sda
# Outputs:
#   text
# Returns:
#   0 ... always :(
#######################################
function process_sata() {
  local _dev=$1
  echo -e "${RED}FAILED - not implemented${ENDCOLOR}"
}

# expects /dev/mapper/key to be a valid key
# expects $1 device
# expects $2 name of decrypted device
function process_pata() {
  local _dev=$1
  echo -e "${RED}FAILED - not implemented${ENDCOLOR}"
}

#######################################
# Open an encrypted luks device
# Globals:
#   none
# Arguments:
#   device - examples: /dev/sda or /dev/hda1 or /dev/nvme0n1
# Outputs:
#   status text
# Returns:
#   0 ... always :(
#######################################
function decrypt() {
  local _dev=$1

  # we need different methods to find the serial number and manufacturer
  # depending on the type of device
  echo $_dev | grep ^/dev/nvme 1>/dev/null && process_nvme $_dev
  echo $_dev | grep ^/dev/sd 1>/dev/null  && process_sata  $_dev
  echo $_dev | grep ^/dev/hd 1>/dev/null  && process_pata  $_dev

}

#######################################
# retrieve the bootfs (root filesystem to boot
# Globals:
#   none
# Arguments:
#   none
# Outputs:
#   pool/dataset
# Returns:
#   0 success
#   1 failure
#######################################
function bootfs() {

  zpool list -H -o bootfs && exit 0
  exit 1

}

#######################################
# text to help orient user if they have
# chosen to import the pool but not to
# proceed with booting the system
#
# Globals:
#   none
# Arguments:
#   none
# Outputs:
#   text
# Returns:
#   0 success
#######################################
function print_help() {
  zpool status
  count="$(zfs list -t snap $bootfs -H -o name | wc -l)"
  zfs list -t snap $(bootfs) -H -o name | tail -n 10

  echo -e "found $count snaphshots for the rootfs. showing the most recent 10"
  echo -e "change root with ${GREEN}zpool set bootfs=dataset${ENDCOLOR}"
  echo -e "copy datasets with ${GREEN}zfs send pool/dataset@snap | zfs recv pool/newdataset${ENDCOLOR}"
  echo -e "chroot with ${GREEN}zpool export pool && zpool import -f -R /newroot pool${ENDCOLOR} then ${GREEN}chroot /newroot /bin/bash${ENDCOLOR}"
  echo -e "${GREEN}resume-boot${ENDCOLOR} at any time to coninue booting"

  exit 0
}

#######################################
# show initial menu to user
#
# Globals:
#   STOP
# Arguments:
#   none
# Outputs:
#   number
# Returns:
#   0 success
#######################################
function show_menu() {
HEIGHT=15
WIDTH=40
CHOICE_HEIGHT=4
BACKTITLE="LUKS initramfs unlocker"
TITLE="initramfs options"
MENU="Choose one of the following options:"

CHOICE=$(dialog --clear \
                --backtitle "$BACKTITLE" \
                --title "$TITLE" \
                --menu "$MENU" \
                $HEIGHT $WIDTH $CHOICE_HEIGHT \
                1 "unlock and boot" \
                2 "unlock and return to shell" \
                2>&1 >/dev/tty)

clear
STOP=NO
case $CHOICE in
        1)
            STOP="NO"
            ;;
        2)
            STOP="YES"
            ;;
esac


}


####################################################
#                                                  #
# start script here                                #
#                                                  #
####################################################

modprobe loop
STOP="YES"

show_menu

echo -ne " ${GREEN}*${ENDCOLOR} opening keyfile, need password: "
# old cryptsetup needs luksOpen
cryptsetup luksOpen --readonly /root/loop.crypt key

echo -e " ${GREEN}*${ENDCOLOR} opening hard drives\n"
echo -e " $\n${YELLOW}=======================================================${ENDCOLOR}"

# find all the luks-encrypted devices
# depends on blkid
let i=1
for _dev in $(blkid --match-token TYPE=crypto_LUKS --output device | sort)
do
  echo -ne "${YELLOW}$i  ${ENDCOLOR}  "
  decrypt "$_dev"
  let i=$(($i+1))
done
echo -e " ${YELLOW}=======================================================${ENDCOLOR}\n"


echo -e " ${GREEN}*${ENDCOLOR} loading zfs module"
/sbin/modprobe zfs

echo -e " ${GREEN}*${ENDCOLOR} importing tank (no mount)"
/sbin/zpool import -f -N tank

if [ $STOP == "YES" ]; then
  print_help
  exit 1
fi

echo -e " ${GREEN}*${ENDCOLOR} closing keyfile"
cryptsetup luksClose /dev/mapper/key
rm /tmp/rescueshell.lock
/usr/sbin/resume-boot
exit 0
