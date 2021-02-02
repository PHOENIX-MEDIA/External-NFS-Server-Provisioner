#!/bin/sh
##########################################################################################
#
# Kubernetes External NFS Server Provisioner
#
# Start script to assign VIP and start NFS server.
#
# Usage: start-cmd.sh
#
# Author:           Bjoern Kraus
# Copyright:        (c) 2021 PHOENIX MEDIA GmbH <https://www.phoenix-media.eu>
#
##########################################################################################

printErrorAndExit() {
    echo "$1"
    sleep 10
    exit 1
}

# Check and prepare environment variables
NSENTER_CMD="$(which nsenter) -t 1"
NFS_SHARED_STORAGE_LOCAL_MOUNT_POINT="/nfs-shared-storage"
NFS_SHARED_STORAGE_DEVICE=$(mount |grep "$NFS_SHARED_STORAGE_LOCAL_MOUNT_POINT" | cut -d" " -f1)
NFS_SHARED_STORAGE_HOST_MOUNT_POINT=$($NSENTER_CMD -m -- mount | grep "$NFS_SHARED_STORAGE_DEVICE" | cut -d" " -f3)
SCRIPT_DIR=$(dirname "$0")

if [ -z "$VIP" ]; then
    printErrorAndExit "Error: Required environment variable VIP is missing."
fi

if [ -z "$NFS_EXPORT_DIR" ]; then
    NFS_EXPORT_DIR="/export"
fi
if [ -z "$NFS_EXPORT_OPTIONS" ]; then
    NFS_EXPORT_OPTIONS="rw,no_root_squash,async,no_subtree_check,fsid=777"
fi
if [ -z "$NFS_PACKAGE_NAME" ]; then
    NFS_PACKAGE_NAME="nfs-kernel-server"
fi

EXPORT_CMD_CLIENT_IPS="*/$NFS_EXPORT_DIR"

if [ -n "$CLIENT_IPS" ]; then
    EXPORT_CMD_CLIENT_IPS=""
    export IFS=","
    for ipAddress in $CLIENT_IPS; do
        EXPORT_CMD_CLIENT_IPS="$EXPORT_CMD_CLIENT_IPS $ipAddress:$NFS_EXPORT_DIR "
    done
fi


# Create VIP
$SCRIPT_DIR/vip.sh up $VIP
rc=$?;
if [ $rc != 0 ]; then
    printErrorAndExit "Failed to assign VIP."
fi

# Mount bind NFS PV
$SCRIPT_DIR/storage.sh mount "$NFS_SHARED_STORAGE_HOST_MOUNT_POINT" "$NFS_EXPORT_DIR"
rc=$?;
if [ $rc != 0 ]; then
    printErrorAndExit "Failed to bind mount PV for NFS server."
fi

# Start NFS server
$SCRIPT_DIR/nfs-server.sh start $NFS_PACKAGE_NAME
rc=$?;
if [ $rc != 0 ]; then
    printErrorAndExit "Failed to start NFS server."
fi

# Export NFS share
$NSENTER_CMD -m -u -n -i -- sh -c "exportfs -v -o $NFS_EXPORT_OPTIONS $EXPORT_CMD_CLIENT_IPS"
rc=$?;
if [ $rc != 0 ]; then
    printErrorAndExit "Failed export NFS share."
fi
