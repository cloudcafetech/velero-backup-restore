# Kubernetes Container Platform backup & restore using Velero

Velero is a convenient backup tool for Kubernetes clusters that compresses and backs up Kubernetes objects to object storage. It also takes snapshots of your cluster's Persistent Volumes using your cloud provider's block storage snapshot features, and can then restore your cluster's objects and Persistent Volumes to a previous state.

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

```scp -i <PEM file PATH> minio/config/CAs/rootCA.pem centos@<Kubentes Master IP>:/home/centos/ ```

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
# Copy rootCA.pem from Kubernetes server centos home folder

cp /home/centos/rootCA.pem .

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

- Download backup script and run.

```
wget https://raw.githubusercontent.com/cloudcafetech/velero-backup-restore/master/backup.sh; chmod +x backup.sh
./backup.sh <kube-cluster> <namespace>
```

### RESTORE:

- Download restore script and run.

```
wget https://raw.githubusercontent.com/cloudcafetech/velero-backup-restore/master/restore.sh; ; chmod +x restore.sh
velero get backup
./restore.sh <backup name>
```


