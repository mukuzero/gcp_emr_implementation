#!/bin/bash

set -e

# Configuration - can be overridden by environment variables
DB_INSTANCE_NAME_PREFIX="${DB_INSTANCE_NAME_PREFIX:-low-tier-db-instance}"
DDL_FILE="${DDL_FILE:-./scripts/ddl.sql}"

# Required environment variables (no defaults for security)
# REGION - GCP region (from GitHub secrets)
# DB_NAME - Database name (from GitHub secrets)
# DB_USER - Database username (from GitHub secrets)
# DB_PASSWORD - Database password (from GitHub secrets)

echo "================================================================"
echo "Cloud SQL Database Setup Script"
echo "================================================================"

# Validate required environment variables
if [ -z "$REGION" ]; then
  echo "Error: REGION environment variable is not set."
  echo "Please set REGION before running this script."
  exit 1
fi

if [ -z "$DB_PASSWORD" ]; then
  echo "Error: DB_PASSWORD environment variable is not set."
  echo "Please set DB_PASSWORD before running this script."
  exit 1
fi

if [ -z "$DB_NAME" ]; then
  echo "Error: DB_NAME environment variable is not set."
  echo "Please set DB_NAME before running this script."
  exit 1
fi

if [ -z "$DB_USER" ]; then
  echo "Error: DB_USER environment variable is not set."
  echo "Please set DB_USER before running this script."
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

  # Stop Cloud SQL Proxy to release port 5432 for load_data.sh
  echo "Stopping Cloud SQL Proxy..."
  kill $PROXY_PID 2>/dev/null || true

  # Execute Data Loading
  echo "Executing Data Loading Script..."
  if ./scripts/load_data.sh; then
    echo "Data loading completed successfully."
  else
    echo "Error: Data loading failed."
    exit 1
  fi
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
