#!/bin/sh
##########################################################################################
#
# Kubernetes External NFS Server Provisioner
#
# This script creates a bind mount for the NFS server.
#
# Usage: storage.sh <COMMAND> <PV_MOUNT_POINT> <NFS_MOUNT_POINT>
#
# COMMAND:          "mount" or "umount" the NFS storage device
# PV_MOUNT_POINT:   Mount point of the persistent volume on the host
# NFS_MOUNT_POINT:  NFS mount point (aka NFS export directory)
#
# Author:           Bjoern Kraus
# Copyright:        (c) 2021 PHOENIX MEDIA GmbH <https://www.phoenix-media.eu>
#
##########################################################################################

NSENTER_CMD="$(which nsenter) -t 1 -m --"

isMounted() {
    $NSENTER_CMD mount | grep " $1 "
}

if [ $# -ne 3 ]
then
    echo "Error in $0 - Please provide a command, PV mount point and a NFS mount point."
    exit 1
fi

cmd=$1
pvMountPoint=$2
nfsMountPoint=$3

if [ "$cmd" = "mount" ]; then
    echo "Bind mount $pvMountPoint to $nfsMountPoint..."
    if isMounted "$nfsMountPoint"; then
        echo "Warning: Bind mount already exists."
        exit
    fi
    if ! $NSENTER_CMD sh -c "ls $nfsMountPoint"; then
        echo "Creating directory $nfsMountPoint..."
        if $NSENTER_CMD mkdir "$nfsMountPoint"; then
            echo "OK"
        else
            echo "Failed!"
            exit 1
        fi
    fi
    if timeout 15 $NSENTER_CMD sh -c "mount --bind $pvMountPoint $nfsMountPoint"; then
        $NSENTER_CMD sh -c "chmod a+rwx $nfsMountPoint"
        echo "Success!"
        exit
    fi
    echo "Error!"
    exit 1
elif [ "$cmd" = "umount" ]; then
    echo "Unmount $nfsMountPoint..."
    if ! isMounted "$nfsMountPoint"; then
        echo "Warning: Bind mount doesn't exists."
        exit
    fi
    if $NSENTER_CMD umount -l $nfsMountPoint; then
        echo "Success!"
	      exit
    fi
    echo "Error!"
    exit 1
else
    echo "Unsupported command '$cmd'"
    exit 1
fi
