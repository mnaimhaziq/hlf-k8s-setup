#!/bin/bash

# Assign arguments to variables
SSH_USER="$1"
SSH_HOST="$2"
package_id_org1="$3"
package_id_org2="$4"
package_id_org3="$5"


NAMESPACE="hlf"
LABEL_SELECTOR_1="name=cli-peer0-org1"
LABEL_SELECTOR_2="name=cli-peer0-org2"
LABEL_SELECTOR_3="name=cli-peer0-org3"

CLI_PEER0_ORG1=$(kubectl get pods -n $NAMESPACE -l $LABEL_SELECTOR_1 -o jsonpath='{.items[0].metadata.name}')
CLI_PEER0_ORG2=$(kubectl get pods -n $NAMESPACE -l $LABEL_SELECTOR_2 -o jsonpath='{.items[0].metadata.name}')
CLI_PEER0_ORG3=$(kubectl get pods -n $NAMESPACE -l $LABEL_SELECTOR_3 -o jsonpath='{.items[0].metadata.name}')

kubectl apply -f 9.cc-deploy/basic -n hlf

export ORDERER_CA=/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem


# Step 16: Approve Chaincode
echo "Approving Chaincode..."
# Approve chaincode for cli-peer0-org1
# kubectl exec -n hlf $CLI_PEER0_ORG1 -- peer lifecycle chaincode approveformyorg --channelID mychannel --name basic --version 1.0 --init-required --package-id $package_id_org1 --sequence 1 -o orderer:7050 --tls --cafile $ORDERER_CA
kubectl exec -n $NAMESPACE -it $CLI_PEER0_ORG1 -- bash -c '
    peer lifecycle chaincode approveformyorg --channelID mychannel --name basic --version 1.0 --init-required --package-id '$package_id_org1' --sequence 1 -o orderer:7050 --tls --cafile $ORDERER_CA'

kubectl exec -n $NAMESPACE -it $CLI_PEER0_ORG2 -- bash -c '
    peer lifecycle chaincode approveformyorg --channelID mychannel --name basic --version 1.0 --init-required --package-id '$package_id_org2' --sequence 1 -o orderer:7050 --tls --cafile '$ORDERER_CA''

kubectl exec -n $NAMESPACE -it $CLI_PEER0_ORG3 -- bash -c '
    peer lifecycle chaincode approveformyorg --channelID mychannel --name basic --version 1.0 --init-required --package-id '$package_id_org3' --sequence 1 -o orderer:7050 --tls --cafile '$ORDERER_CA''


# kubectl exec -n hlf $CLI_PEER0_ORG2 -- peer lifecycle chaincode approveformyorg --channelID mychannel --name basic --version 1.0 --init-required --package-id $package_id_org2 --sequence 1 -o orderer:7050 --tls --cafile $ORDERER_CA

# kubectl exec -n hlf $CLI_PEER0_ORG3 -- peer lifecycle chaincode approveformyorg --channelID mychannel --name basic --version 1.0 --init-required --package-id $package_id_org3 --sequence 1 -o orderer:7050 --tls --cafile $ORDERER_CA

sleep 30

# Check commit readiness for chaincode basic version 1.0
kubectl exec -n hlf $CLI_PEER0_ORG1 -- \
    peer lifecycle chaincode checkcommitreadiness --channelID mychannel --name basic --version 1.0 --init-required --sequence 1 -o orderer:7050 --tls --cafile $ORDERER_CA

# Commit chaincode (only one cli)
kubectl exec -n hlf $CLI_PEER0_ORG1 -- \
    peer lifecycle chaincode commit -o orderer:7050 --channelID mychannel --name basic --version 1.0 --sequence 1 --init-required --tls true --cafile $ORDERER_CA --peerAddresses peer0-org1:7051 --tlsRootCertFiles /organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt \
    --peerAddresses peer0-org2:7051 --tlsRootCertFiles /organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt \
    --peerAddresses peer0-org3:7051 --tlsRootCertFiles /organizations/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt

kubectl exec -n hlf $CLI_PEER0_ORG1 -- \
    peer lifecycle chaincode querycommitted -C mychannel

kubectl exec -n hlf $CLI_PEER0_ORG1 -- \
    peer chaincode invoke -o orderer:7050 --isInit --tls true --cafile $ORDERER_CA -C mychannel -n basic --peerAddresses peer0-org1:7051 --tlsRootCertFiles /organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt --peerAddresses peer0-org2:7051 --tlsRootCertFiles /organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt --peerAddresses peer0-org3:7051 --tlsRootCertFiles /organizations/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt -c '{"Args":["InitLedger"]}' --waitForEvent

kubectl exec -n hlf $CLI_PEER0_ORG1 -- \
    peer chaincode query -C mychannel -n basic -c '{"Args":["GetAllAssets"]}'
