#!/bin/sh
##########################################################################################
#
# Kubernetes External NFS Server Provisioner
#
# Health check to verify NFS server export.
#
# Usage: health-check.sh
#
# Author:           Bjoern Kraus
# Copyright:        (c) 2021 PHOENIX MEDIA GmbH <https://www.phoenix-media.eu>
#
##########################################################################################

if [ -z "$VIP" ]; then
    echo "Error: Required environment variable VIP is missing."
    exit 1
fi

if [ -z "$NFS_EXPORT_DIR" ]; then
    NFS_EXPORT_DIR="/export"
fi

timeout 15 mount $VIP:$NFS_EXPORT_DIR /mnt
rc=$?;
if [ $rc != 0 ]; then
    echo "Mount of NFS share failed. Is the NFS server available?"
    exit 1
fi

timeout 5 echo "This is a test." >> /mnt/health_check_test
rc=$?;
if [ $rc != 0 ]; then
    echo "Failed to write to file share. Is it writable?"
    exit 1
fi

timeout 5 rm -f /mnt/health_check_test
rc=$?;
if [ $rc != 0 ]; then
    echo "Failed to remove test file."
    exit 1
fi

timeout 5 umount -l /mnt
rc=$?;
if [ $rc != 0 ]; then
    echo "Failed to umount NFS share."
    exit 1
fi
