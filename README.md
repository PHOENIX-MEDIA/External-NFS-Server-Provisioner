# External NFS Server Provisioner Helm Repository

Add the Helm repository:

```console
helm repo add external-nfs-server-provisioner https://phoenix-media.github.io/External-NFS-Server-Provisioner/
```

The `values.yaml` contains all required configurations. Update the environment variables to your needs (see previous section).
Especially pay attention to the `persistence`, `storageClass` and `csi-driver-nfs` settings as they will be different in
each K8S environment.

Example `values_custom.yaml`
```yaml
env:
  - name: VIP
    value: 10.11.12.13
storageClass:
  parameters:
    server: 10.11.12.13
```

Deploy the chart with Helm 3.x as usual:

`helm install --create-namespace -n nfs-server -f values_custom.yaml nfs-server external-nfs-server-provisioner/nfs-server-provisioner`
