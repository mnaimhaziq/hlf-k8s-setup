#!/bin/bash

# Check if the correct number of arguments is provided
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <SSH_USER> <SSH_HOST>"
  exit 1
fi

# Assign arguments to variables
SSH_USER=$1
SSH_HOST=$2

# Function to delete all resources in a given namespace
cleanup_kubernetes() {
  echo "Deleting all Kubernetes resources in the 'hlf' namespace..."
  kubectl delete all --all -n hlf
  echo "Deleting Persistent Volume Claim 'mypvc' in the 'hlf' namespace..."
  kubectl delete pvc mypvc -n hlf
  echo "Deleting Persistent Volume 'mypv' in the 'hlf' namespace..."
  kubectl delete pv mypv -n hlf
  echo "Deleting ConfigMap 'builders-config' in the 'hlf' namespace..."
  kubectl delete configmap builders-config -n hlf
}

# Function to clean up NFS share via SSH
cleanup_nfs_share() {
  echo "Connecting to SSH and cleaning up NFS share..."
  ssh ${SSH_USER}@${SSH_HOST} << 'ENDSSH'
  cd /mnt/nfs_share
  rm -rf ./*
  echo "NFS share cleaned up successfully."
ENDSSH
}

# Execute cleanup functions
cleanup_kubernetes
cleanup_nfs_share

echo "Cleanup script completed."
