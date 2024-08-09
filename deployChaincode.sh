#!/bin/bash

if [ $# -ne 2 ]; then
  echo "Usage: $0 <org_name> <chaincode_id>"
  exit 1
fi

org_name=$1
chaincode_id=$2

# Clean chaincode ID by removing newlines and ensuring it's properly quoted
clean_chaincode_id=$(echo "${chaincode_id}" | tr -d '\n' | sed 's/"/\\"/g')

# Define the Deployment YAML content with variables
cat <<EOF > "${org_name}-chaincode-deployment.yaml"
---
#---------------- Chaincode Deployment---------------------
apiVersion: apps/v1
kind: Deployment
metadata:
  name: chaincode-basic-${org_name}
  labels:
    app: chaincode-basic-${org_name}
spec:
  selector:
    matchLabels:
      app: chaincode-basic-${org_name}
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: chaincode-basic-${org_name}
    spec:
      containers:
        - image: mnaimhaziq/basic-cc-hlf:1.0
          imagePullPolicy: Always
          name: chaincode-basic-${org_name}
          env:
            - name: CHAINCODE_ID
              value: "${clean_chaincode_id}"
            - name: CHAINCODE_SERVER_ADDRESS
              value: "0.0.0.0:7052"
          ports:
            - containerPort: 7052
EOF

# Define the Service YAML content with variables
cat <<EOF > "${org_name}-chaincode-service.yaml"
---
#---------------- Chaincode Service ---------------------
apiVersion: v1
kind: Service
metadata:
  name: basic-${org_name}
  labels:
    app: basic-${org_name}
spec:
  ports:
    - name: grpc
      port: 7052
      targetPort: 7052
  selector:
    app: chaincode-basic-${org_name}
EOF

# Store YAML files on NFS server using SSH
scp "${org_name}-chaincode-deployment.yaml" "${org_name}-chaincode-service.yaml" 9.cc-deploy/basic/

# Clean up temporary local YAML files
rm "${org_name}-chaincode-deployment.yaml" "${org_name}-chaincode-service.yaml"
