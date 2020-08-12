#!/bin/bash
# Velero backup restore script

NS=$2
CLUSTER=$1

if [ "$CLUSTER" == "" ]; then
 echo "Usage: backup.sh <CLUSTER NAME> <NAMESPACE>"
 echo "List of clusters:"
 kubectl config get-contexts | grep -v NAME | awk '{print $2}'
 exit
fi

CLUSTERLIST=( $(kubectl config get-contexts | grep -v NAME | awk '{print $2}') )
NSLIST=( $(kubectl get ns | grep -v NAME | awk '{print $1}') )

for CLSNM in ${CLUSTERLIST[@]};
do
 if [ "$CLUSTER" == "$CLSNM" ]; then
  CLUSFOUND=1
 fi
done

if [ "$CLUSFOUND" != "1" ]; then
  echo "Cluster ($CLUSTER) not in list."
  echo "List of clusters:"
  kubectl config get-contexts | grep -v NAME | awk '{print $2}'
  echo exit
  exit
fi

if [ $CLUSTER != $(kubectl config current-context) ]; then
 echo "Wrong Cluster in current-context, change cluster run: kubectl ctx <CLUSTER NAME>"
 echo "List of clusters:"
 kubectl config get-contexts | grep -v NAME | awk '{print $2}'
 exit
fi

if [ "$NS" == "" ]; then
 velero backup create velero-bkp-$CLUSTER.all-resources.$(date +'%d-%m-%Y-%H-%M-%S') --include-resources '*'
else
 for NSNM in ${NSLIST[@]};
 do
  if [ "$NS" == "$NSNM" ]; then
   NSFOUND=1
  fi
 done
 if [ "$NSFOUND" != "1" ]; then
  echo "Namespace ($NS) not avalable in cluster ($CLUSTER)."
  echo "List of namespace in cluster ($CLUSTER):"
  kubectl get ns | grep -v NAME | awk '{print $1}'
  exit
 fi
 velero backup create velero-bkp-$CLUSTER.$NS.full-$(date +'%d-%m-%Y-%H-%M-%S') --snapshot-volumes --include-namespaces $NS
fi

echo ""
echo ""

echo "All backup status"
echo "-----------------"

velero get backup
