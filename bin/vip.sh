#!/bin/sh
##########################################################################################
#
# Kubernetes External NFS Server Provisioner
#
# This script adds and removes an IP alias (tested with Ubuntu 18.04)
#
# Usage: vip.sh <COMMAND> <VIP>
#
# COMMAND:          "up" or "down" the IP alias
# VIP:              Valid IPv4 address
#
# Author:           Bjoern Kraus
# Copyright:        (c) 2021 PHOENIX MEDIA GmbH <https://www.phoenix-media.eu>
#
##########################################################################################

PING_CMD=$(which ping)
IP_CMD=$(which ip)

getInterface() {
    tmpNetIf=$($IP_CMD route get $1 | grep -oE " dev \w+ " | xargs | cut -d " " -f2)
    if [ "$tmpNetIf" = "lo" ]; then
        tmpNetIf=$($IP_CMD addr show |grep $1 | grep -oE "\w+$")
    fi
    echo $tmpNetIf
    unset tmpNetIf
}

isIpConflict() {
    $PING_CMD -c1 $1 > /dev/null
}

setAlias() {
    $IP_CMD link add $3 link $2 type ipvlan mode l2
    $IP_CMD addr add $1/24 dev $3
}

unsetAlias() {
    $IP_CMD link del $1
}

hasHostVip() {
    tmpNetIf=$($IP_CMD route get $1 | grep -oE " dev \w+ " | xargs | cut -d " " -f2)
    if [ "$tmpNetIf" = "lo" ]; then
        retval="true"
    else
        retval="false"
    fi
    echo "$retval"
    unset tmpNetIf
    unset retval
}

if [ $# -ne 3 ]
then
    echo "Error in $0 - Please provide a command,a valid IP address and network interface name."
    exit 1
fi

cmd=$1
vip=$2
nicname=$3

netIf=$(getInterface "$vip")
if [ "$cmd" = "up" ]; then
    echo "Setting VIP $vip on virtual interface $nicname ($netIf)..."
    if [ "$(hasHostVip $vip)" = "true" ]; then
        echo "Warning: VIP is assigned to the host already."
        exit
    fi
    if isIpConflict "$vip"; then
        echo "Error: IP conflicted detected for $vip."
	    exit 1
    fi
    if setAlias $vip $netIf $nicname; then
        echo "Success!"
        exit
    fi
    echo "Error!"
    exit 1
elif [ "$cmd" = "down" ]; then
    echo "Unsetting VIP $vip on interface $netIf..."
    if [ "$(hasHostVip $vip)" = "false" ]; then
        echo "Warning: VIP is not assigned to the host."
        exit
    fi
    if unsetAlias $nicname; then
        echo "Success!"
	    exit
    fi
    echo "Error!"
    exit 1
else
    echo "Unsupported command '$cmd'"
fi
