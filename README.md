# Kubernetes Container Platform backup & restore using Velero

Velero is a convenient backup tool for Kubernetes clusters that compresses and backs up Kubernetes objects to object storage. It also takes snapshots of your cluster's Persistent Volumes using your cloud provider's block storage snapshot features, and can then restore your cluster's objects and Persistent Volumes to a previous state.

## Note: as of now do not use secured (https) setup, not able to success with volume backup with selfsign sertificate
 
## Minio Installation
MinIO is a High Performance Object Storage. It is API compatible with Amazon S3 cloud storage service. Use MinIO to build high performance infrastructure for machine learning, analytics and application data workloads.

### Step #1 Create backup location

First you need to create backup location, it could be any cloud provider object storage location. But here I am going to use on-prem storage location. ```MinIO``` is one of opensource tool which help us to create object storage like AWS S3. To setup ```MinIO``` use following steps. Before execute below command make sure docker is installed in host.

#### Non Secure (http) MinIO

```
mkdir -p /root/minio/data
mkdir -p /root/minio/config

chcon -Rt svirt_sandbox_file_t /root/minio/data
chcon -Rt svirt_sandbox_file_t /root/minio/config

docker run -d -p 9000:9000 --restart=always --name minio1 \
  -e "MINIO_ACCESS_KEY=admin" \
  -e "MINIO_SECRET_KEY=admin2675" \
  -v /root/minio/data:/data \
  -v /root/minio/config:/root/.minio \
  minio/minio server /data
```

#### Secure (https) MinIO

- Create Self-sign certificate.

```
wget https://raw.githubusercontent.com/cloudcafetech/velero-backup-restore/master/create-cert.sh; chmod +x create-cert.sh
./create-cert.sh
```

- Create folders

```
mkdir -p /root/minio/data
mkdir -p /root/minio/config/CAs

chcon -Rt svirt_sandbox_file_t /root/minio/data
chcon -Rt svirt_sandbox_file_t /root/minio/config
```

- Copy certificate to minio certficate folder

```
cp $HOME/tls/public.crt $HOME/tls/private.key /root/minio/config/
cp $HOME/tls/rootCA.pem /root/minio/config/CAs/
```

- Start MinIO docker container 

```
docker run -d -p 443:443 --restart=always --name minio1 \
  -v /root/minio/config:/root/.minio \
  -v /root/minio/data:/data \
  -e "MINIO_ACCESS_KEY=admin" \
  -e "MINIO_SECRET_KEY=admin2675" \
  minio/minio server --certs-dir=/root/.minio --address ":443" /data
```

- Copy rootCA.pem from Minio server to Kubernetes server

```scp -i ```

### Step #2 Login MinIO
Now you can access MinIO using ```MINIO_ACCESS_KEY``` & ```MINIO_SECRET_KEY```.

- For non secured (http)
http://server-ip:9000
 
- For secured (https)
https://server-ip
 
### Step #3 Create Bucket in MinIO

Please create ```velero-cluster1``` bucket inside minio & and change policy with read & write also please do remember bucket name.

OR use command line tool.

```
MinIO=10.128.0.9
wget https://dl.min.io/client/mc/release/linux-amd64/mc; chmod +x mc; mv -v mc /usr/local/bin/mc
mc config host add minio1 https://$MinIO admin bappa2675 --insecure
mc mb minio1/velero-cluster1 --insecure
```

## Velero Setup in Kubernetes
The Velero backup tool consists of a client installed on your local computer and a server that runs in your Kubernetes cluster. To begin, we'll install the local velero client.

### Step #1 Download packege

- Find release version

https://github.com/vmware-tanzu/velero/releases

- Download packege with wget

```
ver=v1.4.2
wget https://github.com/vmware-tanzu/velero/releases/download/$ver/velero-$ver-linux-amd64.tar.gz
tar -xvzf velero-$ver-linux-amd64.tar.gz
mv -v velero-$ver-linux-amd64/velero /usr/local/bin/velero
```

### Step #2 Create secrets

Before we deploy velero into our Kubernetes cluster, we'll first create velero's prerequisite objects. 

```
cat <<EOF > credentials-velero
[default]
aws_access_key_id = admin
aws_secret_access_key = admin2675
EOF
```

### Step #3 Start deployment
It will produce output all of the .yaml files used to create the Velero deployment. Remove ```--dry-run -o yaml``` to run directly.

- For non secured (http)

```
MinIO=10.128.0.9
velero install \
    --provider aws \
    --bucket velero-cluster1 \
    --plugins velero/velero-plugin-for-aws:v1.1.0 \
    --use-restic \
    --secret-file ./credentials-velero \
    --use-volume-snapshots=true \
    --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://$MinIO:9000 \
    --snapshot-location-config region=minio \
    --dry-run -o yaml
```

- For secured (https)

```
# Copy rootCA.pem from Minio server to Kubernetes server


MinIO=10.128.0.9
velero install \
    --provider aws \
    --bucket velero-cluster1 \
    --plugins velero/velero-plugin-for-aws:v1.1.0 \
    --use-restic \
    --secret-file ./credentials-velero \
    --use-volume-snapshots=true \
    --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=https://$MinIO,insecureSkipTLSVerify="true" \
    --cacert rootCA.pem \
    --snapshot-location-config region=minio \
    --dry-run -o yaml
```

#### Note: The velero install command creates a set of CRDs that power the Velero service.

### Step #5 Add backup annotation to pods with volumes automatically
Add backup annotation to pods with volumes automatically

```kubectl create -f https://raw.githubusercontent.com/cloudcafetech/velero-backup-restore/master/velero-volume-controller.yaml```

### Step #6 Verification
After the installation is complete, you can verify that you have number of restic-xxx pods based on your numbers of nodes and 1 velero-xxx pod deployed in the velero namespace. As the restic service is deployed as a daemonset.

```
oc get pod -n velero

oc logs -f <POD NAME>

velero backup-location get
```
#### Special Note: If you have different storage class in remote cluster then edit & run in REMOTE Cluster

```
vi change-storage-class-cm.yaml
kubectl create -f change-storage-class-cm.yaml
``` 

### BACKUP:

To backup volumes with Restic, Velero ask to make an annotation on the pods ```backup.velero.io/backup-volumes=<Volume Name>```
This annotation need to be written in the application deployment yaml file, in ```spec.template.metadata.annotations```

- Useful commands

##### Find volumes in pod/deployment/statefulset which has PVC

```
kubectl get pods -n <NAMESPACE> -o=json | jq -rc \
'.items[] | {pod: .metadata.name, namespace: .metadata.namespace, volume: .spec.volumes[] | select( has ("persistentVolumeClaim") ).name }'

kubectl get pods --all-namespaces -o=json | jq -rc \
'.items[] | {pod: .metadata.name, namespace: .metadata.namespace, volume: .spec.volumes[] | select( has ("persistentVolumeClaim") ).name }'

kubectl get pod <NAME> -n <NAMESPACE> -o=json | jq -rc '.spec.volumes[] | select( has ("persistentVolumeClaim") ).name'

kubectl get deployment <NAME> -n <NAMESPACE> -o=json | jq -rc '.spec.template.spec.volumes[] | select( has ("persistentVolumeClaim") ).name'

kubectl get statefulset <NAME> -n <NAMESPACE> -o=json | jq -rc '.spec.template.spec.volumes[] | select( has ("persistentVolumeClaim") ).name'
```
##### Patching backup annotation to pod/deployment/statefulset with volumes manually 
```kubectl -n <NAMESPACE> patch deployment <NAME> -p '{"spec":{"template":{"metadata":{"annotations":{"backup.velero.io/backup-volumes": "<VOLUME-NAME>"}}}}}'```

##### Patching backup annotation to pods with volumes automatically
```kubectl create -f velero-volume-controller.yaml -n velero```

##### Update Backup Storage Location 
```kubectl edit backupstoragelocation <location-name> -n <velero-namespace> -o yaml```

Example
```kubectl edit backupstoragelocation default -n velero -o yaml```

##### Update Volume Snapshot Location
```kubectl edit volumesnapshotlocation <location-name> -n <velero-namespace> -o yaml```

Example
```kubectl edit volumesnapshotlocation default -n velero -o yaml```

##### Update Credentials
Using kubectl plugings (modify-secret), if not install follow https://github.com/prasenforu/Kube-platform/blob/master/misc/KUBECTL-PLUGINS.md

```
kubectl modify-secret cloud-credentials -n velero
```

Example
```kubectl edit volumesnapshotlocation default -n velero -o yaml```

- Manually backups

```
velero backup create velero-bkp-kube-router --include-namespaces kube-router

velero backup describe velero-bkp-kube-router

velero backup logs velero-bkp-kube-router
```

- Schedule backups

```
velero schedule create planes-daily --schedule="0 1 * * *" --include-namespaces kube-router

velero schedule create planes-daily --schedule="@daily" --include-namespaces kube-router
```

- Backup status

```velero get backup```

- Some backup commands

Backup PVCs in the namespace "abc":

```velero backup create foo --include-namespaces abc --include-resources persistentvolumeclaims```

Backup PVCs and services in the namespace "abc":

```velero backup create foo --include-namespaces abc --include-resources persistentvolumeclaims,services```

Backup PVCs in all namespaces:

```velero backup create foo --include-resources persistentvolumeclaims```

Back up PVCs labeled with "foo=bar" in the namespace "abc":

```velero backup create foo --include-namespaces abc --include-resources persistentvolumeclaims --selector foo=bar```

### RESTORE:

```
velero get backup

velero restore create --from-backup velero-bkp-kube-router
```

Restore a specific object (example: pvc ing svc) from a full-namespace backup

```
velero restore create --from-backup bd-ns-azure-backup1 --include-resources svc --wait

velero restore create --from-backup bd-ns-azure-backup1 --include-resources pvc,ing,svc --wait
```

#### Restic 

- Velero restic repositories for volume snapshot

```velero restic repo get```

#### Enable debugging

```
kubectl edit deployment/velero -n velero
...
   containers:
     - name: velero
       image: velero/velero:latest
       command:
         - /velero
       args:
         - server
         - --log-level # Add this line
         - debug       # Add this line
...
```

#### Troubleshooting

Download the backup (as a tarball), need to extract the tarball ```velero backup download <BACKUP NAME>```

```
velero backup download <BACK NAME>
velero backup describe <backupName>
velero backup logs <backupName>
velero restore describe <restoreName>
velero restore logs <restoreName>
```

#### change PersistentVolumes reclaim policy

```
kubectl patch pv <PV NAME> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
kubectl patch pv <PV NAME> -p '{"spec":{"persistentVolumeReclaimPolicy":"Delete"}}'
```

#### Monitor backup annotation (detect pvc that are missing the restic backup annotation)
https://github.com/bitsbeats/velero-pvc-watcher

#### Adding backup annotation to pods with volumes automatically
https://github.com/duyanghao/velero-volume-controller

#### Restic integration & limitation
https://velero.io/docs/master/restic/
https://velero.io/docs/master/restic/#limitations

#### Disaster recovery
https://velero.io/docs/master/disaster-case

#### Cluster migration
https://velero.io/docs/master/migration-case

#### Hooks thread

- MongoDB
https://github.com/vmware-tanzu/velero/issues/1404
https://github.com/vmware-tanzu/velero/issues/1327

- PostgresDB
https://github.com/vmware-tanzu/velero/issues/2116

- MySQLDB


#### ETCD backup
Not supported 

### Limitations
Below are known limitations of Velero

- Velero currently supports a single set of credentials per provider. It’s not yet possible to use different credentials for different locations.
- Volume snapshots are limited by where your provider allows you to create snapshots. For example, AWS and Azure do not allow you to create a volume snapshot in a different region than where the volume is.
- Each Velero backup has one BackupStorageLocation, and one VolumeSnapshotLocation per volume provider. It is not possible to send a single Velero backup to multiple backup storage locations simultaneously, or a single volume snapshot to multiple locations simultaneously.
- Cross-provider snapshots are not supported.
- ETCD backup & restore supported by velero

#### ETCD backup & restore
Let's assume that there is only one master. If you have many you can repeat the same process on all the master nodes you have.
In order to back up your etcd, we need the certificates.

- ETCD backup 
```sudo cp -r /etc/kubernetes/pki backup/
sudo docker run --rm -v $(pwd)/backup:/backup --network host -v /etc/kubernetes/pki/etcd:/etc/kubernetes/pki/etcd --env ETCDCT_API=3 k8s.gcr.io/etcd-amd64:3.2.18 \
etcdctl --endpoint=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/healthcheck-client.py snapshot save /backup/etcd.db
```
- ETCD restore

To restore the etcd backup, you will need to perform the backup you just took the inverse way. You will just need to replace save by restore and then move the data back to /var/lib/etcd/
