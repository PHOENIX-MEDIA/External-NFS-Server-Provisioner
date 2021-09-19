# Kubernetes External NFS Server Provisioner

## Introduction

NFS servers exist since decades and is maybe the most widespread file share technology. While NFS server 
implementations can be considered as "commodity software" the existing solutions for Kubernetes, which most often 
provision an NFS server inside a container, don't seem to match the stability of Kernel based NFS servers shipped with 
Linux distributions.

In Kubernetes everything is about automation, fail-safe implementations and reliability. At a minimum every service
should get restarted when the service/pod/node becomes unavailable, so the service continues after a short downtime.
The same is expected for storage implementations. Downtimes can be acceptable if the availability stays within
the agreed [SLO](https://sre.google/sre-book/service-level-objectives/) (service level objective) and issues get
automatically and quickly resolved.

Therefore, the project's goal is a fail-tolerant setup of a very robust NFS service with a maximum downtime of
approx. 2 minutes on maintenance or error. Furthermore, it aims for maximum reliability during regular service and
data protection.

> Note on stability: The project is a proof of concept and in beta state. It still requires more testing of the
> fail-over process. However, once the NFS server has been deployed successfully it should work stable.

## Prerequisites

This provisioner requires a redundant cloud storage solution (see [examples](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#types-of-persistent-volumes))
which has been already deployed to the K8S cluster. Ideally a StorageClass exists to create a RWO PVC/PV, which can be 
attached to any node the provisioner (see below) gets deployed.


## High Level Architecture

The NFS server will get installed and started by the [start-up scripts](bin/start-cmd.sh) of the provisioner on the host 
OS of the K8S node the provisioner gets deployed to. A virtual IP will be automatically assigned to the host's network 
interface before the NFS server gets started. The NFS server will export a file share on the PV via a `mount --bind`. 
A StorageClass for a "NFS client provisioner" needs to be deployed to K8S separately to allow applications to create 
PVC/PVs on demand.

For error and fail-over handling the provisioner is deployed as a StatefulSet. Kubernetes' internal mechanisms for error
detection and scheduling will automatically restart the StatefulSet on one of the remaining nodes and the NFS server becomes
available again.

## The (dirty) details

### "NFS Server Provisioner" StatefulSet

The provisioner image is deployed as StatefulSet with a RWO PV attached which will be used for the NFS
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
liveness probe will fail and K8S will redeploy the provisioner. The [start-up script](bin/start-cmd.sh) should then 
repair any problem or output an error message which helps to resolve issues.

As a result the [start-cmd.sh](bin/start-cmd.sh) will start NFS server on the Linux host which completely operates independent of K8S
except its health checks and other K8S mechanisms like draining etc. (see section "Draining and fail-over").

> Please note that this is not the best practise approach from a security standpoint, but a viable approach within a
trusted environment.

### Defining a NFS storage class

To create new PVCs/PVs on the NFS server the [CSI NFS driver](https://github.com/kubernetes-csi/csi-driver-nfs) is recommended.
In the storage class the NFS server IP and the mount point have to be set as [parameters](https://github.com/kubernetes-csi/csi-driver-nfs/blob/master/docs/driver-parameters.md)
(also see [charts/nfs-server-provisioner/values.yaml](charts/nfs-server-provisioner/values.yaml)).
Since the driver creates sub-directories for each PVC dynamically underneath the base directory of the NFS server, no
conflicts are expected.

Make sure to set a [reclaimPolicy](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#reclaim-policy)
which satisfies your safety requirements.

### Draining and fail-over

Instead of deploying a HA/fail-over solution on the host OS this project uses Kubernetes' native mechanisms. A
liveness probe checks the health of the NFS server, the export of the share and the accessibility of the PV. If the 
StatefulSet gets stopped a [preStop hook](bin/stop-cmd.sh) ensures the NFS server gets stopped on the host and the VIP 
gets released. This mechanism is automatically triggered if the node gets drained, so the StatefulSet is deployed on 
another node immediately. Existing NFS mounts should continue to operate once the VIP and the NFS server become available again. 
However, to avoid "[toil](https://sre.google/sre-book/eliminating-toil/)" it is recommended to add an accessibility 
check for the NFS mount in the liveness probe of the application pod to restart the pod to overcome stale situations. 
These liveness probes can be tricky to implement and should be carefully tested for situations where the NFS servers 
restarts to avoid unnecessary restarts of the application pod.

In case of a node failure/restart the *preStop hook* won't be triggered. We assume the NFS server and VIP have been 
stopped as well. As soon as the StatefulSet gets rescheduled on another node the PV and VIP should be available again
to start the NFS server on the new node. Of course there can be situations where this assumption leads to a conflicts. 
However, the issue resolution should be rather easy to resolve them manually (see Troubleshooting section).

## Environment variables

The provisioner image accepts the following environment variables:

| Env name           | Description                                                                        | Default value                                     |
|--------------------|------------------------------------------------------------------------------------|---------------------------------------------------|
| VIP                | Virtual IP address for the NFS server.<br>Example: 192.168.10.100<br>**Required**. |                                                   |
| NIC_NAME           | Virtual Network Interface name.<br>*Optional*.                                     | nfsservernic                                      |
| NFS_EXPORT_DIR     | Directory for the NFS server export.<br>*Optional*.                                | /export                                           |
| NFS_EXPORT_OPTIONS | NFS export options used for the exportfs.<br>*Optional*.                           | rw,no_root_squash,async,no_subtree_check,fsid=777 |
| NFS_PACKAGE_NAME   | NFS server package name in Linux distro's package manager.<br>*Optional*.          | nfs-kernel-server                                 |
| CLIENT_IPS         | Comma separated list of client IPs for the exportfs command.<br>*Optional*.        |                                                   |

## Deployment

> The latest Docker image is available on [Dockerhub](https://hub.docker.com/repository/docker/phoenixmedia/external-nfs-server-provisioner).

### Helm

> The Helm chart hasn't been uploaded to a repository yet. Just clone the git repository and deploy the chart right from the charts directory.

The `values.yaml` contains all required configurations. Update the environment variables to your needs (see previous section).
Especially pay attention to the `persistence`, `storageClass` and `csi-driver-nfs` settings as they will be different in
each K8S environment.
Deploy the chart with Helm 3.x as usual:

`helm install -n nfs-provisioner nfs-provisioner .`

This will deploy the CSI driver for NFS, create a StorageClass, create a PVC for the NFS data and deploy the NFS server
provisioner. After a couple of minutes the NFS server should be ready. The new `file` StorageClass can be used to create
PVCs for deployments.

K8S resources like StorageClasses can not be modified once they have been deployed. If you want to start-over just 
uninstall the Helm chart and deploy it again with modified values:

```
helm uninstall --wait -n nfs-provisioner nfs-provisioner .
helm install -n nfs-provisioner nfs-provisioner .
```

## Troubleshooting

Since the NFS server is running on the host OS, debugging requires to SSH to the host system.

### Check and release the VIP

Check if the VIP is assigned to the host network:

```ip a | grep <VIP>```

To attach it manually use:

```
ip link add nfsservernic link <ifname> type ipvlan mode l2
ip addr add <VIP>/24 dev nfsservernic
```

To detach it use:

```ip link del nfsservernic```

### Check and release NFS export mount point

The NFS server uses a configurable mount point (default: `/export`) on the host. Check if the PV has been bound to this
mount point:

```mount <mount point>```

To release the mount on the host simply use `umount <mount point>`.

### Check the NFS server

To see if the NFS server is running check the output of `systemctl status nfs-kernel-server` (the service name may
differ depending on the host OS).

The NFS exports can be verified by executing `exportfs -s`.
