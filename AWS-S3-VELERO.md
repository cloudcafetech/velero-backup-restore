# Setup Velero Backup location in S3

## Install AWS CLI & configure properly
Download & install AWS CLI & configure properly with your ```access key```,  ```secret access key``` & ```region```

## Create S3 bucket

Velero requires an object storage bucket to store backups in, preferrably unique to a single Kubernetes cluster. 

```aws s3api create-bucket --bucket velero-pkar --region us-east-1```

## Create IAM user

```aws iam create-user --user-name velero```

## Create IAM policy

```
BUCKET=velero-pkar
cat > velero-policy.json << EOF
{
     "Version": "2012-10-17",
     "Statement": [
         {
             "Effect": "Allow",
             "Action": [
                 "ec2:DescribeVolumes",
                 "ec2:DescribeSnapshots",
                 "ec2:CreateTags",
                 "ec2:CreateVolume",
                 "ec2:CreateSnapshot",
                 "ec2:DeleteSnapshot"
             ],
             "Resource": "*"
         },
         {
             "Effect": "Allow",
             "Action": [
                 "s3:GetObject",
                 "s3:DeleteObject",
                 "s3:PutObject",
                 "s3:AbortMultipartUpload",
                 "s3:ListMultipartUploadParts"
             ],
             "Resource": [
                 "arn:aws:s3:::${BUCKET}/*"
             ]
         },
         {
             "Effect": "Allow",
             "Action": [
                 "s3:ListBucket"
             ],
             "Resource": [
                 "arn:aws:s3:::${BUCKET}"
             ]
         }
     ]
 }
EOF
```

## Attach policies with user (velero) for the bucket (velero-pkar) whcih we created in previous command

```
aws iam put-user-policy \
   --user-name velero \
   --policy-name velero \
   --policy-document file://velero-policy.json
```

## Creating an access for the above user (velero)

```aws iam create-access-key --user-name velero```

The result should look like:

```
{
    "AccessKey": {
        "UserName": "velero",
        "Status": "Active",
        "CreateDate": "2020-04-28T14:30:33Z",
        "SecretAccessKey": "<AWS_SECRET_ACCESS_KEY>",
        "AccessKeyId": "<AWS_ACCESS_KEY_ID>"
    }
}
```

## Copy the AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY from the above step and save in a file named ```credentials-velcro-aws``` in your local directory:

```
cat <<EOF > credentials-velero-aws
[default]
aws_access_key_id=<AWS_ACCESS_KEY_ID>
aws_secret_access_key=<AWS_SECRET_ACCESS_KEY>
EOF
```

## Start Installation

- Find release version
https://github.com/vmware-tanzu/velero/releases

- Download velero 
```
ver=v1.2.0
wget https://github.com/vmware-tanzu/velero/releases/download/$ver/velero-$ver-linux-amd64.tar.gz
tar -xvzf velero-$ver-linux-amd64.tar.gz
mv -v velero-$ver-linux-amd64/velero /usr/local/bin/velero 
```

- Start velero installation

Make sure put proper ```bucket name```, ```region```, ```access_key``` & ```secret_access_key``` 

```
velero install \
    --provider aws \
    --bucket velero-pkar \
    --plugins velero/velero-plugin-for-aws:v1.0.1 \
    --use-restic \
    --secret-file ./credentials-velero-aws \
    --use-volume-snapshots=true \
    --backup-location-config region=us-east-1 \
    --snapshot-location-config region=us-east-1
```
