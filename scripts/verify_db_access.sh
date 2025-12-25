#!/bin/bash

set -e

# Default values, can be overridden by env vars
REGION="${REGION:-us-central1}"
CLUSTER_NAME="${CLUSTER_NAME:-low-tier-cluster}"
# We match the prefix used in terraform
DB_INSTANCE_NAME_PREFIX="low-tier-db-instance"

echo "----------------------------------------------------------------"
echo "Starting Connectivity Verification"
echo "Region: $REGION"
echo "Cluster: $CLUSTER_NAME"
echo "----------------------------------------------------------------"

# 1. Get the Cloud SQL Instance Name
if [ -n "$DB_INSTANCE_NAME" ]; then
  echo "Using instance name from environment: $DB_INSTANCE_NAME"
else
  echo "Finding Cloud SQL instance..."
  DB_INSTANCE_NAME=$(gcloud sql instances list --format="value(name)" --filter="name~^${DB_INSTANCE_NAME_PREFIX}")
fi

if [ -z "$DB_INSTANCE_NAME" ]; then
  echo "Error: Cloud SQL instance starting with '$DB_INSTANCE_NAME_PREFIX' not found."
  echo "Make sure Terraform has been applied."
  exit 1
fi
echo "Found Instance: $DB_INSTANCE_NAME"

# 2. Get the Private IP
echo "Fetching Private IP..."
# Filter for type:PRIVATE to ensure we get the internal IP
DB_IP=$(gcloud sql instances describe "$DB_INSTANCE_NAME" --format="json" | jq -r '.ipAddresses[] | select(.type == "PRIVATE") | .ipAddress')

if [ -z "$DB_IP" ]; then
  echo "Error: Could not find Private IP for instance $DB_INSTANCE_NAME."
  echo "Check if Private IP is enabled and VPC peering is successful."
  exit 1
fi
echo "Target DB IP: $DB_IP"

# 3. Create a temporary Python script for connectivity test
cat <<EOF > check_connectivity.py
import socket
import sys

host = "$DB_IP"
port = 5432

print(f"Attempting to connect to {host}:{port}...")

try:
    sock = socket.create_connection((host, port), timeout=10)
    print(f"SUCCESS: Connected to {host}:{port}")
    sock.close()
except Exception as e:
    print(f"FAILURE: Could not connect to {host}:{port}")
    print(f"Error: {e}")
    sys.exit(1)
EOF

# 4. Submit the job to Dataproc
echo "Submitting Dataproc job to verify connection..."
# We use pyspark job type as it's a lightweight way to run python code on the cluster
gcloud dataproc jobs submit pyspark check_connectivity.py \
  --cluster="$CLUSTER_NAME" \
  --region="$REGION"

if [ $? -eq 0 ]; then
    echo "----------------------------------------------------------------"
    echo "VERIFICATION SUCCESSFUL: Dataproc can reach Cloud SQL."
    echo "----------------------------------------------------------------"
else
    echo "----------------------------------------------------------------"
    echo "VERIFICATION FAILED: Dataproc cannot reach Cloud SQL."
    echo "----------------------------------------------------------------"
    exit 1
fi

# Cleanup
rm check_connectivity.py
