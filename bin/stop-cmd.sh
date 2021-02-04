#!/bin/sh
##########################################################################################
#
# Kubernetes External NFS Server Provisioner
#
# Stop script to shut down VIP and NFS server.
#
# Usage: stop-cmd.sh
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
SCRIPT_DIR=$(dirname "$0")

if [ -z "$VIP" ]; then
    printErrorAndExit "Error: Required environment variable VIP is missing."
fi

if [ -z "$NFS_EXPORT_DIR" ]; then
    NFS_EXPORT_DIR="/export"
fi


# Stop VIP
$SCRIPT_DIR/vip.sh down $VIP
rc=$?;
if [ $rc != 0 ]; then
    printErrorAndExit "Failed to unassign VIP."
fi

# Stop NFS server
$SCRIPT_DIR/nfs-server.sh stop
rc=$?;
if [ $rc != 0 ]; then
    printErrorAndExit "Failed to stop NFS server."
fi

# Unmount NFS PV
$SCRIPT_DIR/storage.sh umount /not-important $NFS_EXPORT_DIR
rc=$?;
if [ $rc != 0 ]; then
    printErrorAndExit "Failed to umount PV of NFS server."
fi
