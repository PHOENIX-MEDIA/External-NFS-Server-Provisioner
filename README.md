# Kubernetes External NFS Server Provisioner

## Introduction

NFS servers exist since decades and NFS shares is maybe the most widespread file share technology. While the NFS server 
implementations can be considered as "commodity software" the existing solutions for Kubernetes, which most often 
provision an NFS server inside a container, don't seem to match the stability of Kernel based NFS servers shipped with 
Linux distributions.

In Kubernetes everything is about automation, fail-safe implementations and reliability. At a minimum every service
should get restarted when the service/pod/node becomes unavailable, so the service continues after a short downtime.
The same is expected for storage implementations. Downtimes can be acceptable if the availability stays within
the agreed SLO (service level objective) and problems get automatically and quickly resolved.

Therefore, the project's goal is a fail-tolerant setup of a very robust NFS service with a maximum downtime of
approx. 2 minutes on maintenance or error. Furthermore, it aims for maximum reliability during regular service and
data protection.

> Note on stability: The project is a proof of concept and in beta state. It still requires intensive testing of the
> fail-over process. However, once the NFS server has been deployed successfully it should work stable.
> Please also have a look at the *Open Issues* section below.

## Prerequisites

This provisioner requires a redundant cloud storage solution which has been already deployed to the K8S cluster. A 
storage class should exist to create a RWO PVC/PV, which can be attached to any node the provisioner (see below) gets
deployed.


## High Level Architecture

The NFS server will get installed and started by the [start-up scripts](bin/start-cmd.sh) of the provisioner on the host 
OS of the K8S node the provisioner gets deployed to. A virtual IP will be automatically assigned to the host's network 
interface before the NFS server gets started. The NFS server will export a file share on the PV via a `mount --bind`. 
A storage class for a "NFS client provisioner" needs to be deployed to K8S separately to allow applications to create 
PVC/PVs.

For error and fail-over handling the provisioner is deployed as a StatefulSet. Kubernetes' internal mechanisms for error
detection and rescheduling will automatically restart the StatefulSet on an available node, so the NFS server gets
redeployed again by the provisioner's start-up scripts on the new host.

## The (dirty) details

### "NFS Server Provisioner" StatefulSet

The provisioner image is deployed as StatefulSet (scale 1) with a RWO PV attached which will be used for the NFS
server's persistence storage. The StatefulSet needs to run with privileged permissions and `hostPID: true` to execute
commands directly on the host as well as `hostNetwork: true` to assign the VIP to the host's network interface.
The image ships with a set of shell scripts (see /bin directory) which brings up everything on pod start. To export the 
NFS share from the attached PV the start-up script of the image tries to identify the PV mount on the host and 
`mount --bind` it to the configured NFS server export mount point on the host.

To execute commands on the host directly the scripts use `nsenter -t 1 -m -u -n -i sh` to break out of the pod's
context. For some users this may be a rather brutal approach, but it is simple and works without additional tricks.

On the host basically the following commands are executed:

```
ip addr add <vip>/24 dev <ifname>
mount --bind <PV mount of the pod> <$NFS_EXPORT_DIR for NFS server>
systemctl start nfs-kernel-server
exportfs -o <$NFS_EXPORT_OPTIONS> [<node IP>:<$NFS_EXPORT_DIR> ..]
```

The health check tries to mount the NFS export inside the pod and to write/read a file. On error or timeout the 
liveness probe will fail and K8S will restart the provisioner. The [start-up script](bin/start-cmd.sh) should then 
repair any problems or output and error which helps to resolve conflicts.

As a result the [start-cmd.sh](bin/start-cmd.sh) will start NFS server on the Linux host which completely operates independent of K8S
except its health checks and other K8S mechanisms like draining etc. (see section "Draining and fail-over").

### Defining a NFS storage class

To make the NFS share available to workloads we recommend installing an "NFS client provisioner"
(e.g. https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner) or a "CSI NFS driver"
(e.g. https://github.com/kubernetes-csi/csi-driver-nfs; project is in alpha state but works pretty good for simple
scenarios). In the storage class the VIP and mount point configured for the provisioner's StatefulSet have to be
configured to expose the NFS server's share to the workloads (see 
[deploy/yaml/StorageClass.yaml](deploy/yaml/StorageClass.yaml)). Since the drivers usually create sub-directories in
the base share directory for each PVC dynamically, no conflicts are expected.

> Please note that this is not a best practise approach from a security standpoint, but a viable approach within a
trusted environment.

### Draining and fail-over

Instead of deploying a HA/fail-over solution on the host OS the project uses Kubernetes' native mechanisms. A
liveness probe checks the health of the NFS server, the export of the share and the accessibility of the PV. If the 
StatefulSet gets stopped a [preStop hook](bin/stop-cmd.sh) ensures the NFS server gets stopped on the host, and the VIP 
gets released. This mechanism is automatically triggered if the node gets drained, so the StatefulSet is deployed on 
another node. Existing NFS mounts should continue to operate once the VIP and the NFS server become available again. 
However, to avoid "[toil](https://sre.google/sre-book/eliminating-toil/)" it is recommended to add an accessibility 
check for the NFS mount in the liveness probe of the application pod to restart the pod to overcome stale situations. 
These liveness probes can be tricky to implement and should be carefully tested for situations where the NFS servers 
restarts to avoid unnecessary restarts of the application pod.

In case of a node failure/restart the *preStop hook* won't be triggered. We assume the NFS server and VIP have been 
stopped as well. As soon as the StatefulSet gets rescheduled on another node the PV and VIP should be available again
to start the NFS server on the new node. Of course there can be situations this assumption leads to a conflicts. 
However, the issue resolution should be rather easy to resolve manually (see Troubleshooting section).

## Environment variables

The provisioner image accepts the following environment variables:

| Env name           | Description                                                                        | Default value                                     |
|--------------------|------------------------------------------------------------------------------------|---------------------------------------------------|
| VIP                | Virtual IP address for the NFS server.<br>Example: 192.168.10.100<br>**Required**. |                                                   |
| NFS_EXPORT_DIR     | Directory for the NFS server export.<br>*Optional*.                                | /export                                           |
| NFS_EXPORT_OPTIONS | NFS export options used for the exportfs.<br>*Optional*.                           | rw,no_root_squash,async,no_subtree_check,fsid=777 |
| NFS_PACKAGE_NAME   | NFS server package name in Linux distro's package manager.<br>*Optional*.          | nfs-kernel-server                                 |
| CLIENT_IPS         | Comma separated list of client IPs for the exportfs command.<br>*Optional*.        |                                                   |

## Deployment

> The latest Docker image is available on [Dockerhub](https://hub.docker.com/repository/docker/phoenixmedia/external-nfs-server-provisioner).

The NFS server needs a persistent volume to save its shares. The RWO PV must be available on all nodes the StatefulSet 
gets deployed to. Create a PVC from a robust storage backend (see [deploy/yaml/PVC.yaml](deploy/yaml/PVC.yaml) for an 
example).

The only required environment variable is the VIP. Choose an IP which all nodes within your Kubernetes cluster can reach
without Firewall restrictions.

Once the PVC has been created and the VIP added to the YAML (see [deploy/yaml/StatefulSet.yaml](deploy/yaml/StatefulSet.yaml)
for an example), you are good to go.

> A Helm chart will be added in the near future to make the deployment more convenient.

## Open issues

- Failover process requires more testing.
- Deployment YAML is very basic, Helm chart is desirable.

## Troubleshooting

Since the NFS server is running on the host OS, debugging requires to SSH to host.

### Check and release the VIP

Check if the VIP is assigned to the host network:

```ip a | grep <VIP>```

To attach it manually use:

```ip addr add <VIP>/24 dev <ifname>```

To detach it use:

```ip addr del <VIP>/24 dev <ifname>```

### Check and release NFS export mount point

The NFS server uses a configurable mount point (default: `/export`) on the host. Check if the PV has been bound to this
mount point:

```mount <mount point>```

To release the mount on the host simply use `umount <mount point>`.

### Check the NFS server

To see if the NFS server is running check the output of `systemctl status nfs-kernel-server` (the service name may
differ depending on the host OS).

The NFS exports can be verified by executing `exportfs -s`.
