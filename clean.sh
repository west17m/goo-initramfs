#!/bin/bash
# clean (prior to commit)
source /etc/genkernel.conf
rm -rf ${INITRAMFS_OVERLAY}/{usr/lib64,usr/bin,lib64,lib,bin,etc/initrd.d,usr,sbin}
exit 0
