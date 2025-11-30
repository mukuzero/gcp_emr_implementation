#!/bin/bash

set -e

# Configuration - can be overridden by environment variables
DB_INSTANCE_NAME_PREFIX="${DB_INSTANCE_NAME_PREFIX:-low-tier-db-instance}"
DB_NAME="${DB_NAME:-ehmr}"
DB_USER="${DB_USER:-mukunthan}"
DDL_FILE="${DDL_FILE:-./scripts/ddl.sql}"
REGION="${REGION:-us-central1}"
# DB_PASSWORD should be set as environment variable (from GitHub secrets)

echo "================================================================"
echo "Cloud SQL Database Setup Script"
echo "================================================================"

# Validate required environment variables
if [ -z "$DB_PASSWORD" ]; then
  echo "Error: DB_PASSWORD environment variable is not set."
  echo "Please set DB_PASSWORD before running this script."
  exit 1
fi

# Validate DDL file exists
if [ ! -f "$DDL_FILE" ]; then
  echo "Error: DDL file not found at: $DDL_FILE"
  echo "Please ensure ddl.sql exists in the current directory."
  exit 1
fi

echo "Using DDL file: $DDL_FILE"

# Find the Cloud SQL instance
echo "Finding Cloud SQL instance..."
INSTANCE_NAME=$(gcloud sql instances list --format="value(name)" --filter="name~^${DB_INSTANCE_NAME_PREFIX}")

if [ -z "$INSTANCE_NAME" ]; then
  echo "Error: Cloud SQL instance starting with '$DB_INSTANCE_NAME_PREFIX' not found."
  echo "Make sure Terraform has been applied and the database is created."
  exit 1
fi

echo "Found instance: $INSTANCE_NAME"

# Get the private IP
echo "Fetching private IP address..."
PRIVATE_IP=$(gcloud sql instances describe "$INSTANCE_NAME" --format="json" | jq -r '.ipAddresses[] | select(.type == "PRIVATE") | .ipAddress')

if [ -z "$PRIVATE_IP" ]; then
  echo "Error: Could not find private IP for instance $INSTANCE_NAME"
  echo "Ensure the instance has private IP enabled."
  exit 1
fi

echo "Private IP: $PRIVATE_IP"

# Method 1: Using Cloud SQL Proxy (recommended)
echo ""
echo "================================================================"
echo "Executing DDL using Cloud SQL Proxy..."
echo "================================================================"

# Start Cloud SQL Proxy in the background
echo "Starting Cloud SQL Proxy..."
cloud_sql_proxy --address 127.0.0.1 --port 5432 "$INSTANCE_NAME" &
PROXY_PID=$!

# Wait for proxy to be ready
echo "Waiting for Cloud SQL Proxy to be ready..."
sleep 5

# Execute DDL
echo "Executing DDL from $DDL_FILE..."
export PGPASSWORD="$DB_PASSWORD"

if psql -h 127.0.0.1 -p 5432 -U "$DB_USER" -d "$DB_NAME" -f "$DDL_FILE"; then
  echo "================================================================"
  echo "DDL executed successfully!"
  echo "================================================================"
else
  echo "Error: Failed to execute DDL"
  kill $PROXY_PID 2>/dev/null || true
  exit 1
fi

# Cleanup
echo "Stopping Cloud SQL Proxy..."
kill $PROXY_PID 2>/dev/null || true
unset PGPASSWORD

echo "Database setup complete."
