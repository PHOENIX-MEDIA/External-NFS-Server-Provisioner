#!/bin/sh
##########################################################################################
#
# Kubernetes External NFS Server Provisioner
#
# This script installs, starts and stops an NFS server on a node (tested with Ubuntu 18.04)
#
# Usage: nfs-server.sh <COMMAND> <NFS_PACKAGE_NAME>
#
# COMMAND:          "start" or "stop" the NFS server
# NFS_PACKAGE_NAME: NFS server package name in Linux distro's package manager
#                   (e.g. "nfs-kernel-server")
#
# Author:           Bjoern Kraus
# Copyright:        (c) 2021 PHOENIX MEDIA GmbH <https://www.phoenix-media.eu>
#
##########################################################################################

NFS_PACKAGE_NAME="nfs-kernel-server"
NSENTER_CMD="$(which nsenter) -t 1 -m -u -n -i --"
SYSTEMCTL_CMD=$($NSENTER_CMD which systemctl)
DPKG_CMD=$($NSENTER_CMD which dpkg)
APT_GET_CMD=$($NSENTER_CMD which apt-get)

installServer() {
    if $NSENTER_CMD sh -c "$DPKG_CMD -l | grep \"ii\" | grep \"$NFS_PACKAGE_NAME\""; then
        echo "$NFS_PACKAGE_NAME already installed."
    else
        echo "Install $NFS_PACKAGE_NAME ..."
        $NSENTER_CMD $APT_GET_CMD update
        $NSENTER_CMD $APT_GET_CMD install -y $NFS_PACKAGE_NAME
        echo "Done."
    fi
}

startServer() {
    echo "Starting NFS server..."
    $NSENTER_CMD $SYSTEMCTL_CMD start $NFS_PACKAGE_NAME
}

stopServer() {
    echo "Stopping NFS server..."
    $NSENTER_CMD $SYSTEMCTL_CMD stop $NFS_PACKAGE_NAME
}

if [ $# -lt 1 ]; then
    echo "Error in $0 - Please provide a valid command."
    exit 1
fi

cmd=$1

if [ -n "$2" ]; then
    NFS_PACKAGE_NAME="$2"
fi

if [ "$cmd" = "start" ]; then
    installServer
    if startServer; then
        echo "Success!"
    else
        echo "Failed to start NFS server."
    fi
elif [ "$cmd" = "stop" ]; then
    if stopServer; then
        echo "Success!"
    else
        echo "Failed to stop NFS server."
    fi
else
    echo "Unsupported command '$cmd'"
    exit 1
fi
