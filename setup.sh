#!/bin/bash

# Assign arguments to variables
SSH_USER="$1"
SSH_HOST="$2"
# exec >setup.log 2>&1
generate_connection_json_for_org() {
    org=$1

    ssh "${SSH_USER}@${SSH_HOST}" "
        cat > /mnt/nfs_share/chaincode/basic/packaging/connection.json << EOF
{
    \"address\": \"basic-${org}:7052\",
    \"dial_timeout\": \"10s\",
    \"tls_required\": false,
    \"client_auth_required\": false,
    \"client_key\": \"-----BEGIN EC PRIVATE KEY----- ... -----END EC PRIVATE KEY-----\",
    \"client_cert\": \"-----BEGIN CERTIFICATE----- ... -----END CERTIFICATE-----\",
    \"root_cert\": \"-----BEGIN CERTIFICATE---- ... -----END CERTIFICATE-----\"
}
EOF
    "
}

install_and_query() {
  local CLI_PEER=$1
  local ORG=$2

  echo "Installing chaincode on $ORG..."
  kubectl exec -n $NAMESPACE $CLI_PEER -- bash -c 'cd /opt/gopath/src/github.com/chaincode/basic/packaging && peer lifecycle chaincode install basic-org1.tgz'

  echo "Querying installed chaincodes on $ORG..."
  local output=$(kubectl exec -n $NAMESPACE -it $CLI_PEER -- bash -c 'peer lifecycle chaincode queryinstalled --output json')

  echo "Raw output from $ORG: $output"

  # Extract package_id if JSON is valid
  if echo "$output" | jq . >/dev/null 2>&1; then
    local package_id=$(echo "$output" | jq -r ".installed_chaincodes[0].package_id")
    echo "$package_id"
  else
    echo "Invalid JSON returned for $ORG"
    echo ""
  fi
}

wait_for_apply() {
    local resource=$1
    local namespace=$2
    echo "Waiting for $resource in namespace $namespace to be ready..."
    until kubectl get $resource -n $namespace &> /dev/null; do
        sleep 5
    done
    echo "$resource is ready."
}

# Step 1: Configure K8s Cluster
echo "Configuring K8s Cluster..."
kubectl config use-context kubernetes-admin@kubernetes # Replace with your context name if needed

# Step 3: Create PV and PVC
echo "Creating PV and PVC..."
kubectl apply -f 1.nfs/ -n hlf
wait_for_apply pv hlf
wait_for_apply pvc hlf

# Step 4: Copy prerequisites to NFS server
echo "Copying prerequisites to NFS server..."
sudo cp -r prerequisite/* /mnt/nfs_clientshare/
sleep 5
ssh ${SSH_USER}@${SSH_HOST} 'cd /mnt/nfs_share && sudo chmod +x scripts/ -R'

ssh ${SSH_USER}@${SSH_HOST} '
    cd /mnt/nfs_share &&
    mkdir organizations &&
    cp -r fabric-ca/ organizations/ &&
    rm -rf fabric-ca/ &&
    chmod 777 organizations/ -R &&
    ls -l organizations/
'

# Step 5: Deployment of CA Fabric Server
echo "Deploying CA Fabric Server..."
kubectl apply -f 2.ca/ -n hlf
wait_for_apply pv hlf

# Step 6: Generating Certificates for peers and orderers
echo "Generating Certificates..."
kubectl apply -f 3.certificates/ -n hlf
sleep 10

# Step 7: Create Artifacts
echo "Creating Artifacts..."
kubectl apply -f 4.artifacts/ -n hlf
sleep 120

# Step 8: Starting Up Orderers
echo "Starting up Orderers..."
kubectl apply -f 5.orderer/ -n hlf
sleep 10
kubectl get pods -n hlf # Optionally list pods for verification

# Step 9: Configuration Prerequisites
echo "Configuring Prerequisites..."
kubectl apply -f 6.configmap/ -n hlf
sleep 10

# Step 10: Starting Up Peers
echo "Starting up Peers..."
kubectl apply -f 7.peers/org1 -n hlf
kubectl apply -f 7.peers/org2 -n hlf
kubectl apply -f 7.peers/org3 -n hlf
sleep 30

NAMESPACE="hlf"
LABEL_SELECTOR_1="name=cli-peer0-org1"
LABEL_SELECTOR_2="name=cli-peer0-org2"
LABEL_SELECTOR_3="name=cli-peer0-org3"
echo "Get Pods Name based on label selectors..."
# # Get the pod names based on the label selectors
CLI_PEER0_ORG1=$(kubectl get pods -n $NAMESPACE -l $LABEL_SELECTOR_1 -o jsonpath='{.items[0].metadata.name}')
CLI_PEER0_ORG2=$(kubectl get pods -n $NAMESPACE -l $LABEL_SELECTOR_2 -o jsonpath='{.items[0].metadata.name}')
CLI_PEER0_ORG3=$(kubectl get pods -n $NAMESPACE -l $LABEL_SELECTOR_3 -o jsonpath='{.items[0].metadata.name}')

echo CLI PEER0_ORG1 === $CLI_PEER0_ORG1
echo CLI PEER0_ORG2 === $CLI_PEER0_ORG2
echo CLI PEER0_ORG3 === $CLI_PEER0_ORG3
# Step 11: Create App Channel
echo "Creating App Channel..."
kubectl exec -n $NAMESPACE -it $CLI_PEER0_ORG1 -- bash -c './scripts/createAppChannel.sh'

sleep 10

# Join App Channel (for all peers)
echo "Joining App Channel for all peers..."

kubectl exec -it $CLI_PEER0_ORG1 -n hlf -- peer channel join -b ./channel-artifacts/mychannel.block
kubectl exec -it $CLI_PEER0_ORG1 -n hlf -- peer channel list
kubectl exec -it $CLI_PEER0_ORG2 -n hlf -- peer channel join -b ./channel-artifacts/mychannel.block
kubectl exec -it $CLI_PEER0_ORG2 -n hlf -- peer channel list
kubectl exec -it $CLI_PEER0_ORG3 -n hlf -- peer channel join -b ./channel-artifacts/mychannel.block
kubectl exec -it $CLI_PEER0_ORG3 -n hlf -- peer channel list
sleep 10
# Step 12: Update Anchor Peers
echo "Updating Anchor Peers..."
kubectl exec -n $NAMESPACE -it $CLI_PEER0_ORG1 -- bash -c './scripts/updateAnchorPeer.sh Org1MSP'
kubectl exec -n $NAMESPACE -it $CLI_PEER0_ORG2 -- bash -c './scripts/updateAnchorPeer.sh Org2MSP'
kubectl exec -n $NAMESPACE -it $CLI_PEER0_ORG3 -- bash -c './scripts/updateAnchorPeer.sh Org3MSP'
sleep 10

# Step 13: Package Chaincode15
echo "Packaging Chaincode..."
# scp connection.json "${SSH_USER}@${SSH_HOST}:/mnt/nfs_share/chaincode/basic/packaging/connection.json"

ssh ${SSH_USER}@${SSH_HOST} '
    cd /mnt/nfs_share/chaincode/basic/packaging &&
    tar cfz code.tar.gz connection.json &&
    tar cfz basic-org1.tgz code.tar.gz metadata.json &&
    rm code.tar.gz && rm connection.json
'

# Create connection.json for org2 locally and then execute the SSH commands
echo "Generate Connection JSON FOR ORG2..."
generate_connection_json_for_org "org2"

# scp connection.json "${SSH_USER}@${SSH_HOST}:/mnt/nfs_share/chaincode/basic/packaging/connection.json"

ssh ${SSH_USER}@${SSH_HOST} '
    cd /mnt/nfs_share/chaincode/basic/packaging &&
    tar cfz code.tar.gz connection.json &&
    tar cfz basic-org2.tgz code.tar.gz metadata.json &&
    rm code.tar.gz && rm connection.json
'

# Create connection.json for org3 locally and then execute the SSH commands
echo "Generate Connection JSON FOR ORG3..."
generate_connection_json_for_org "org3"

# scp connection.json "${SSH_USER}@${SSH_HOST}:/mnt/nfs_share/chaincode/basic/packaging/connection.json"

ssh ${SSH_USER}@${SSH_HOST} '
    cd /mnt/nfs_share/chaincode/basic/packaging &&
    tar cfz code.tar.gz connection.json &&
    tar cfz basic-org3.tgz code.tar.gz metadata.json &&
    rm code.tar.gz && rm connection.json &&
    ls -l
'

# Step 14: Install Chaincode to all peers
echo "Installing Chaincode to all peers..."
# Install and query package ID on org1
kubectl exec -n hlf $CLI_PEER0_ORG1 -- bash -c 'cd /opt/gopath/src/github.com/chaincode/basic/packaging &&
    peer lifecycle chaincode install basic-org1.tgz'

output1=$(kubectl exec -n $NAMESPACE -it $CLI_PEER0_ORG1 -- bash -c '
    cd /opt/gopath/src/github.com/chaincode/basic/packaging &&
    peer lifecycle chaincode queryinstalled --output json | jq -r ".installed_chaincodes[0].package_id"
')
package_id_org1=$(echo "$output1" | tail -n 1 | tr -d '[:space:]')


# Install and query package ID on org2
kubectl exec -n hlf $CLI_PEER0_ORG2 -- bash -c 'cd /opt/gopath/src/github.com/chaincode/basic/packaging &&
    peer lifecycle chaincode install basic-org2.tgz'

output2=$(kubectl exec -n $NAMESPACE -it $CLI_PEER0_ORG2 -- bash -c '
    cd /opt/gopath/src/github.com/chaincode/basic/packaging &&
    peer lifecycle chaincode queryinstalled --output json | jq -r ".installed_chaincodes[0].package_id"
')
package_id_org2=$(echo "$output2" | tail -n 1 | tr -d '[:space:]')


# Install and query package ID on org3
kubectl exec -n hlf $CLI_PEER0_ORG3 -- bash -c 'cd /opt/gopath/src/github.com/chaincode/basic/packaging &&
    peer lifecycle chaincode install basic-org3.tgz'

output3=$(kubectl exec -n $NAMESPACE -it $CLI_PEER0_ORG3 -- bash -c '
    cd /opt/gopath/src/github.com/chaincode/basic/packaging &&
    peer lifecycle chaincode queryinstalled --output json | jq -r ".installed_chaincodes[0].package_id"
')
package_id_org3=$(echo "$output3" | tail -n 1 | tr -d '[:space:]')


# sleep 30
sleep 10
echo $package_id_org1
echo $package_id_org2
echo $package_id_org3

# # sleep 15

# ./deployChaincode.sh org1 $package_id_org1
# ./deployChaincode.sh org2 $package_id_org2
# ./deployChaincode.sh org3 $package_id_org3


# kubectl apply -f 9.cc-deploy/basic -n hlf

# export ORDERER_CA=/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem


# # Step 16: Approve Chaincode
# echo "Approving Chaincode..."
# kubectl exec -n $NAMESPACE -it $CLI_PEER0_ORG1 -- bash -c '
#     peer lifecycle chaincode approveformyorg --channelID mychannel --name basic --version 1.0 --init-required --package-id '$package_id_org1' --sequence 1 -o orderer:7050 --tls --cafile $ORDERER_CA'

# kubectl exec -n $NAMESPACE -it $CLI_PEER0_ORG2 -- bash -c '
#     peer lifecycle chaincode approveformyorg --channelID mychannel --name basic --version 1.0 --init-required --package-id '$package_id_org2' --sequence 1 -o orderer:7050 --tls --cafile '$ORDERER_CA''

# kubectl exec -n $NAMESPACE -it $CLI_PEER0_ORG3 -- bash -c '
#     peer lifecycle chaincode approveformyorg --channelID mychannel --name basic --version 1.0 --init-required --package-id '$package_id_org3' --sequence 1 -o orderer:7050 --tls --cafile '$ORDERER_CA''

# sleep 30

# # Check commit readiness for chaincode basic version 1.0
# kubectl exec -n hlf $CLI_PEER0_ORG1 -- \
#     peer lifecycle chaincode checkcommitreadiness --channelID mychannel --name basic --version 1.0 --init-required --sequence 1 -o orderer:7050 --tls --cafile $ORDERER_CA

# # Commit chaincode (only one cli)
# kubectl exec -n hlf $CLI_PEER0_ORG1 -- \
#     peer lifecycle chaincode commit -o orderer:7050 --channelID mychannel --name basic --version 1.0 --sequence 1 --init-required --tls true --cafile $ORDERER_CA --peerAddresses peer0-org1:7051 --tlsRootCertFiles /organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt \
#     --peerAddresses peer0-org2:7051 --tlsRootCertFiles /organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt \
#     --peerAddresses peer0-org3:7051 --tlsRootCertFiles /organizations/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt

# kubectl exec -n hlf $CLI_PEER0_ORG1 -- \
#     peer lifecycle chaincode querycommitted -C mychannel

# kubectl exec -n hlf $CLI_PEER0_ORG1 -- \
#     peer chaincode invoke -o orderer:7050 --isInit --tls true --cafile $ORDERER_CA -C mychannel -n basic --peerAddresses peer0-org1:7051 --tlsRootCertFiles /organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt --peerAddresses peer0-org2:7051 --tlsRootCertFiles /organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt --peerAddresses peer0-org3:7051 --tlsRootCertFiles /organizations/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt -c '{"Args":["InitLedger"]}' --waitForEvent

# kubectl exec -n hlf $CLI_PEER0_ORG1 -- \
#     peer chaincode query -C mychannel -n basic -c '{"Args":["GetAllAssets"]}'
