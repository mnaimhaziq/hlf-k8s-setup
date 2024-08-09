# Setting Up a Kubernetes Cluster with NFS and Hyperledger Fabric

This guide will walk you through setting up a local Kubernetes cluster, configuring an NFS server and clients, deploying Hyperledger Fabric components, and working with chaincode.

## Table of Contents

1. [Spawn Kubernetes Cluster](#spawn-kubernetes-cluster)
2. [Create NFS Server](#create-nfs-server)
    - [NFS Server Setup](#nfs-server-setup)
    - [NFS Client (Ubuntu)](#nfs-client-ubuntu)
    - [NFS Client (MacOS)](#nfs-client-macos)
3. [Create Persistent Volume and Persistent Volume Claim](#create-pv-and-pvc)
4. [Copy Prerequisites to NFS Server](#copy-prerequisites-to-nfs-server)
5. [Deploy CA Fabric Server](#deploy-ca-fabric-server)
6. [Generate Certificates for Peers and Orderers](#generate-certificates)
7. [Create Artifacts (Genesis Block and Channel Transactions)](#create-artifacts)
8. [Start Up Orderers](#start-orderers)
9. [Configuration Prerequisites](#configuration-prerequisites)
10. [Start Up Peers](#start-peers)
11. [Create Application Channel](#create-app-channel)
12. [Join Application Channel](#join-app-channel)
13. [Update Anchor Peers](#update-anchor-peers)
14. [Package Chaincode](#package-chaincode)
15. [Install Chaincode to All Peers](#install-chaincode)
16. [Create Chaincode Deployment](#create-chaincode-deployment)
17. [Approve Chaincode](#approve-chaincode)
18. [Commit Chaincode](#commit-chaincode)
19. [Initialize Ledger](#initialize-ledger)
20. [Invoke and Query Chaincode](#invoke-and-query-chaincode)
21. [Port Forwarding](#port-forwarding)

## Spawn Kubernetes Cluster

1. Copy the kubeconfig file to your local kubeconfig:
    ```sh
    cp ~/Downloads/national-blockchain-infrastructure-kubeconfig.yaml ~/.kube/config
    ```
2. Verify the nodes:
    ```sh
    kubectl get nodes
    ```

## Create NFS Server

### NFS Server Setup

1. Update and install the NFS server:
    ```sh
    sudo apt update
    sudo apt install nfs-kernel-server
    ```
2. Configure the NFS share:
    ```sh
    sudo mkdir -p /mnt/nfs_share
    sudo chown -R nobody:nogroup /mnt/nfs_share/
    sudo chmod 777 /mnt/nfs_share/
    ```
3. Export the NFS share:
    ```sh
    echo "/mnt/nfs_share *(rw,sync,no_subtree_check,insecure)" | sudo tee -a /etc/exports
    sudo exportfs -a
    sudo systemctl restart nfs-kernel-server
    ```

### NFS Client (Ubuntu)

1. Update and install the NFS client:
    ```sh
    sudo apt update
    sudo apt install nfs-common
    ```
2. Mount the NFS share:
    ```sh
    sudo mkdir -p /mnt/nfs_clientshare
    sudo mount <NFS_SERVER_IP>:/mnt/nfs_share /mnt/nfs_clientshare
    ls -l /mnt/nfs_clientshare/
    ```

### NFS Client (MacOS)

1. Create the mount directory and mount the NFS share:
    ```sh
    mkdir nfs_clientshare
    sudo mount -o nolocks -t nfs <NFS_SERVER_IP>:/mnt/nfs_share ./nfs_clientshare
    ```

## Create PV and PVC

1. Apply the Persistent Volume and Persistent Volume Claim:
    ```sh
    kubectl apply -f pv.yaml
    kubectl apply -f pvc.yaml
    ```

## Copy Prerequisites to NFS Server
kubectl cp /home/naim-zulkefle/hlf-k8s-setup/prerequisite hlf/task-pv-pod:/usr/share/nginx/html
mv * /usr/share/nginx/html
1. Copy prerequisites:
    ```sh
    cp -r prerequisite/* /mnt/nfs_clientshare/
    ```
2. Verify the copy:
    ```sh
    ls /mnt/nfs_clientshare/
    ```
3. Make scripts executable on the NFS server:
    ```sh
    sudo chmod +x /mnt/nfs_share/scripts/ -R
    ```

## Deploy CA Fabric Server

1. On the NFS server, prepare the directories:
    ```sh
    mkdir organizations
    cp -r fabric-ca/ organizations/
    rm -rf fabric-ca/
    chmod 777 organizations/ -R
    ```
2. Deploy the CA Fabric server:
    ```sh
    cd 2.ca/
    kubectl apply -f .
    ```

## Generate Certificates

1. Generate certificates using jobs:
    ```sh
    cd 3.certificates/
    kubectl apply -f .
    ```
2. Verify the creation of `ordererOrganizations` and `peerOrganizations` in the `organizations` directory on the NFS server.

## Create Artifacts

1. Create channel artifacts and the genesis block:
    ```sh
    cd 4.artifacts
    kubectl apply -f .
    ```

## Start Orderers

1. Start the orderers:
    ```sh
    cd 5.orderer
    kubectl apply -f .
    ```
2. Verify that all orderers are up.

## Configuration Prerequisites

1. Apply the configuration map:
    ```sh
    cd 6.configmap
    kubectl apply -f .
    ```
2. Verify the creation of the `builder-config` configmap.

## Start Peers

1. Start peers for each organization:
    ```sh
    cd 7.peer
    kubectl apply -f org1/
    kubectl apply -f org2/
    kubectl apply -f org3/
    ```

## Create Application Channel

1. In the CLI peer, create the application channel:
    ```sh
    ./scripts/createAppChannel.sh
    ```

## Join Application Channel

1. For each peer CLI, join the application channel:
    ```sh
    peer channel join -b ./channel-artifacts/mychannel.block
    ```
2. Verify success:
    ```sh
    peer channel list
    ```

## Update Anchor Peers

1. Update anchor peers for each organization:
    ```sh
    ./scripts/updateAnchorPeer.sh Org1MSP
    ./scripts/updateAnchorPeer.sh Org2MSP
    ./scripts/updateAnchorPeer.sh Org3MSP
    ```

## Package Chaincode
kubectl cp /home/naim-zulkefle/hlf-k8s-setup/prerequisite/chaincode/basic/packaging/basic-org2.tgz hlf/task-pv-pod:/usr/share/nginx/html/chaincode/basic/packaging 
1. On the NFS server, package the chaincode:
    ```sh
    cd chaincode/basic/packaging
    tar cfz code.tar.gz connection.json
    tar cfz basic-org1.tgz code.tar.gz metadata.json
    rm code.tar.gz
    nano connection.json  # Change the address to org2 and save
    tar cfz code.tar.gz connection.json
    tar cfz basic-org2.tgz code.tar.gz metadata.json
    rm code.tar.gz
    nano connection.json  # Change the address to org3 and save
    tar cfz code.tar.gz connection.json
    tar cfz basic-org3.tgz code.tar.gz metadata.json
    ```
2. Verify the packages:
    ```sh
    ls -l packaging/
    ```

## Install Chaincode

1. Install chaincode on all peers:
    ```sh
    cd /opt/gopath/src/github.com/chaincode/basic/packaging
    peer lifecycle chaincode install basic-org1.tgz
    peer lifecycle chaincode install basic-org2.tgz
    peer lifecycle chaincode install basic-org3.tgz
    ```
2. Note the package IDs for each peer.

## Create Chaincode Deployment

1. Create a repository on Docker Hub (e.g., `basic-cc-hlf`).
2. Build and push the Docker image:
    ```sh
    docker login
    docker build -t <your-docker-username>/basic-cc-hlf:1.0 .
    docker push <your-docker-username>/basic-cc-hlf:1.0
    ```
3. Deploy the chaincode, pasting the respective package IDs.

## Approve Chaincode

1. Approve the chaincode for each organization:
    ```sh
    peer lifecycle chaincode approveformyorg --channelID mychannel --name basic --version 1.0 --init-required --package-id <package-id-org1> --sequence 1 -o orderer:7050 --tls --cafile $ORDERER_CA
    peer lifecycle chaincode approveformyorg --channelID mychannel --name basic --version 1.0 --init-required --package-id <package-id-org2> --sequence 1 -o orderer:7050 --tls --cafile $ORDERER_CA
    peer lifecycle chaincode approveformyorg --channelID mychannel --name basic --version 1.0 --init-required --package-id <package-id-org3> --sequence 1 -o orderer:7050 --tls --cafile $ORDERER_CA
    ```

## Commit Chaincode

1. Check commit readiness:
    ```sh
    peer lifecycle chaincode checkcommitreadiness --channelID mychannel --name basic --version 1.0 --init-required --sequence 1 -o orderer:7050 --tls --cafile $ORDERER_CA
    ```
2. Commit the chaincode (from one CLI):
    ```sh
    peer lifecycle chaincode commit -o orderer:7050 --channelID mychannel --name basic --version 1.0 --sequence 1 --init-required --tls true --cafile $ORDERER_CA --peerAddresses peer0-org1:
    --tlsRootCertFiles /organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt --peerAddresses peer0-org2:7051 --tlsRootCertFiles /organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt --peerAddresses peer0-org3:7051 --tlsRootCertFiles /organizations/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt
    ```

3. Verify the commit:
    ```sh
    peer lifecycle chaincode querycommitted -C mychannel
    ```

## Initialize Ledger

1. Initialize the ledger:
    ```sh
    peer chaincode invoke -o orderer:7050 --isInit --tls true --cafile $ORDERER_CA -C mychannel -n basic --peerAddresses peer0-org1:7051 --tlsRootCertFiles /organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt --peerAddresses peer0-org2:7051 --tlsRootCertFiles /organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt --peerAddresses peer0-org3:7051 --tlsRootCertFiles /organizations/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt -c '{"Args":["InitLedger"]}' --waitForEvent
    ```

## Invoke and Query Chaincode

1. Invoke the chaincode to create an asset:
    ```sh
    peer chaincode invoke -o orderer:7050 --tls true --cafile $ORDERER_CA -C mychannel -n basic --peerAddresses peer0-org1:7051 --tlsRootCertFiles /organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt --peerAddresses peer0-org2:7051 --tlsRootCertFiles /organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt --peerAddresses peer0-org3:7051 --tlsRootCertFiles /organizations/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt -c '{"Args":["CreateAsset","asset100","red","50","tom","300"]}' --waitForEvent
    ```
2. Query the chaincode to retrieve assets:
    ```sh
    peer chaincode query -C mychannel -n basic -c '{"Args":["GetAllAssets"]}'
    ```

## Port Forwarding

1. Port forward the API service:
    ```sh
    kubectl port-forward services/api 4000
    ```

2. Port forward the CouchDB service:
    ```sh
    kubectl port-forward services/peer0-org1 5984:5984
    ```

## Conclusion

By following the steps in this guide, you will have set up a local Kubernetes cluster, configured an NFS server and clients, deployed Hyperledger Fabric components, and performed chaincode operations. This setup can serve as a foundation for developing and testing Hyperledger Fabric applications in a Kubernetes environment.

    
