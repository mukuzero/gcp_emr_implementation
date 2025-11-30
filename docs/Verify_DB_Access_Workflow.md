# Verify Database Access Workflow Documentation

## Overview

The `verify_db_access.sh` script validates network connectivity between Google Cloud Dataproc and Cloud SQL PostgreSQL. It submits a PySpark job to the Dataproc cluster that attempts to connect to the Cloud SQL instance's private IP on port 5432, proving that the VPC networking is correctly configured.

## Purpose

- **Network Validation**: Verify Dataproc can reach Cloud SQL on the private network
- **VPC Peering Check**: Confirm VPC peering between Dataproc and Cloud SQL networks
- **Post-Deployment Testing**: Automated connectivity verification after infrastructure deployment
- **CI/CD Integration**: Ensure infrastructure is functional before proceeding with data operations

## Script Location

```
scripts/verify_db_access.sh
```

## Prerequisites

- **Dataproc Cluster** running in the same region
- **Cloud SQL Instance** with private IP configured
- **VPC Peering** established between Dataproc and Cloud SQL networks
- **gcloud CLI** authenticated with appropriate permissions
- **jq** installed for JSON parsing

## Usage

### GitHub Actions

```yaml
- name: Verify Database Connectivity
  env:
    GOOGLE_CREDENTIALS: ${{ secrets.GOOGLE_CREDENTIALS }}
  run: |
    echo "$GOOGLE_CREDENTIALS" > gcloud-key.json
    gcloud auth activate-service-account --key-file=gcloud-key.json
    chmod +x scripts/verify_db_access.sh
    ./scripts/verify_db_access.sh
    rm gcloud-key.json
```

### Local Testing

```bash
# Using defaults
./scripts/verify_db_access.sh

# With custom values
export REGION="us-west1"
export CLUSTER_NAME="my-cluster"
./scripts/verify_db_access.sh
```

## Workflow Breakdown

### Step 1: Configuration

```bash
REGION="${REGION:-us-central1}"
CLUSTER_NAME="${CLUSTER_NAME:-low-tier-cluster}"
DB_INSTANCE_NAME_PREFIX="low-tier-db-instance"
```

**What happens:**
- Sets default region and cluster name
- Allows override via environment variables
- Defines Cloud SQL instance name prefix for discovery

**Configurable via environment:**
- `REGION` - GCP region (default: us-central1)
- `CLUSTER_NAME` - Dataproc cluster name (default: low-tier-cluster)

### Step 2: Find Cloud SQL Instance

```bash
DB_INSTANCE_NAME=$(gcloud sql instances list --format="value(name)" --filter="name~^${DB_INSTANCE_NAME_PREFIX}")

if [ -z "$DB_INSTANCE_NAME" ]; then
  echo "Error: Cloud SQL instance starting with '$DB_INSTANCE_NAME_PREFIX' not found."
  exit 1
fi
```

**What happens:**
- Searches for Cloud SQL instance by name prefix
- Uses regex filter `~^` to match instances starting with prefix
- Exits if instance not found (infrastructure not deployed)

**Example:**
```
Finding Cloud SQL instance...
Found Instance: low-tier-db-instance-ac543943
```

**Why dynamic discovery:**
- Terraform appends random suffix to instance names
- Script adapts to different environments automatically
- No hardcoded instance names needed

### Step 3: Get Private IP Address

```bash
DB_IP=$(gcloud sql instances describe "$DB_INSTANCE_NAME" --format="json" | jq -r '.ipAddresses[] | select(.type == "PRIVATE") | .ipAddress')

if [ -z "$DB_IP" ]; then
  echo "Error: Could not find Private IP for instance $DB_INSTANCE_NAME."
  exit 1
fi
```

**What happens:**
- Fetches Cloud SQL instance metadata
- Parses JSON output with `jq`
- Extracts private IP address (not public)
- Validates private IP exists

**jq filter breakdown:**
```bash
.ipAddresses[]                  # Iterate through all IP addresses
| select(.type == "PRIVATE")    # Filter only private IPs
| .ipAddress                     # Extract IP address value
```

**Example output:**
```
Fetching Private IP...
Target DB IP: 10.219.0.3
```

**Why private IP:**
- Verifies VPC peering is working
- Public IP would bypass VPC network
- Tests actual production connectivity path

### Step 4: Generate Python Connectivity Test

```bash
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
```

**What happens:**
- Creates temporary Python script dynamically
- Embeds Cloud SQL private IP in the script
- Uses socket programming to test TCP connection
- Sets 10-second timeout for connection attempt

**Script functionality:**
- `socket.create_connection()` - Attempts TCP connection
- Success closes socket and exits with code 0
- Failure prints error and exits with code 1

**Why Python:**
- Available on all Dataproc clusters by default
- Simple socket API for TCP connectivity tests
- PySpark job type provides easy execution

### Step 5: Submit PySpark Job to Dataproc

```bash
gcloud dataproc jobs submit pyspark check_connectivity.py \
  --cluster="$CLUSTER_NAME" \
  --region="$REGION"
```

**What happens:**
- Uploads Python script to Dataproc cluster
- Executes script on cluster nodes
- Tests connectivity from Dataproc's VPC
- Returns job status (success/failure)

**gcloud command details:**
- `submit pyspark` - Submit PySpark job (Python execution)
- `--cluster` - Target Dataproc cluster
- `--region` - GCP region of cluster

**Example output:**
```
Job [abc123] submitted.
Waiting for job output...
Attempting to connect to 10.219.0.3:5432...
SUCCESS: Connected to 10.219.0.3:5432
Job [abc123] finished successfully.
```

### Step 6: Check Job Result

```bash
if [ $? -eq 0 ]; then
    echo "VERIFICATION SUCCESSFUL: Dataproc can reach Cloud SQL."
else
    echo "VERIFICATION FAILED: Dataproc cannot reach Cloud SQL."
    exit 1
fi
```

**What happens:**
- Checks exit code of previous command (`$?`)
- Exit code 0 = success, connectivity verified
- Exit code ≠ 0 = failure, connectivity issue

**Success output:**
```
----------------------------------------------------------------
VERIFICATION SUCCESSFUL: Dataproc can reach Cloud SQL.
----------------------------------------------------------------
```

**Failure output:**
```
----------------------------------------------------------------
VERIFICATION FAILED: Dataproc cannot reach Cloud SQL.
----------------------------------------------------------------
```

### Step 7: Cleanup

```bash
rm check_connectivity.py
```

**What happens:**
- Removes temporary Python script
- Keeps working directory clean

## Complete Workflow Diagram

```
┌─────────────────────────────────────┐
│   User/CI runs verify_db_access.sh │
└─────────────┬───────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│   Set Configuration Defaults        │
│   REGION, CLUSTER_NAME              │
└─────────────┬───────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│   Find Cloud SQL Instance           │
│   gcloud sql instances list         │
└─────────────┬───────────────────────┘
              │
         ┌────┴────┐
         │         │
     Found    Not Found
         │         │
         │         ▼
         │    ┌─────────────────────────┐
         │    │   Exit with Error        │
         │    └─────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│   Get Private IP Address            │
│   Parse with jq                     │
└─────────────┬───────────────────────┘
              │
         ┌────┴────┐
         │         │
     Found    Not Found
         │         │
         │         ▼
         │    ┌─────────────────────────┐
         │    │   Exit with Error        │
         │    └─────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│   Generate Python Test Script      │
│   check_connectivity.py             │
└─────────────┬───────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│   Submit PySpark Job to Dataproc   │
│   Execute connectivity test         │
└─────────────┬───────────────────────┘
              │
         ┌────┴────┐
         │         │
    Success   Failure
         │         │
         │         ▼
         │    ┌─────────────────────────┐
         │    │   Report Failure         │
         │    │   Exit with code 1       │
         │    └─────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│   Report Success                    │
│   Delete temp script                │
└─────────────┬───────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│   Verification Complete             │
│   Return exit code 0                │
└─────────────────────────────────────┘
```

## What This Script Tests

### ✅ Verifies Working:

1. **VPC Peering**: Dataproc VPC can route to Cloud SQL VPC
2. **Firewall Rules**: Port 5432 is allowed between networks
3. **Private IP**: Cloud SQL private IP is reachable
4. **Network Configuration**: Overall network setup is correct

### ❌ Does NOT Test:

1. **Authentication**: Doesn't verify database credentials
2. **Database Content**: Doesn't check if database is accessible
3. **SSL/TLS**: Doesn't validate encrypted connections
4. **SQL Queries**: Doesn't test actual database operations

**For database-level testing**, use [`setup_db.sh`](./Setup_DB_Workflow.md)

## Integration with CI/CD

This script runs as part of the GitHub Actions workflow **after** infrastructure deployment:

```yaml
jobs:
  terraform:
    steps:
      # ... terraform apply ...
      
      - name: Setup Database Schema
        # ... setup_db.sh ...
      
      - name: Verify Database Connectivity  # ← This step
        run: ./scripts/verify_db_access.sh
```

**Position in pipeline:**
1. Terraform Apply (create infrastructure)
2. Setup Database Schema (run DDL)
3. **Verify Database Connectivity** (this script)

## Required Permissions

The service account needs:

- `dataproc.jobs.create` - Submit PySpark jobs
- `dataproc.jobs.get` - Check job status
- `cloudsql.instances.get` - Describe Cloud SQL instances
- `cloudsql.instances.list` - List Cloud SQL instances

**Predefined role:** `roles/dataproc.editor` + `roles/cloudsql.viewer`

## Network Requirements

### VPC Peering

Cloud SQL must be configured with:
- **Private IP enabled**
- **VPC peering** to Dataproc VPC
- **Allocated IP range** for Cloud SQL

### Firewall Rules

Implicit allow rule needed for:
- **Source**: Dataproc subnet CIDR
- **Destination**: Cloud SQL private IP range
- **Protocol**: TCP
- **Port**: 5432

## Troubleshooting

### Issue: "Cloud SQL instance not found"

**Causes:**
- Terraform not applied yet
- Wrong region
- Instance name prefix mismatch

**Solution:**
```bash
# Check what instances exist
gcloud sql instances list

# Verify Terraform state
cd terraform
terraform show | grep db_instance
```

### Issue: "Could not find Private IP"

**Causes:**
- Cloud SQL not configured with private IP
- VPC peering not established
- Instance still initializing

**Solution:**
```bash
# Check Cloud SQL IP configuration
gcloud sql instances describe INSTANCE_NAME

# Verify VPC peering
gcloud compute networks peerings list --network=dataproc-sql-network
```

### Issue: "VERIFICATION FAILED: Dataproc cannot reach Cloud SQL"

**Causes:**
- VPC peering not working
- Firewall blocking port 5432
- Dataproc in different network
- Cloud SQL in different region

**Debug steps:**
```bash
# 1. Check VPC peering status
gcloud compute networks peerings list

# 2. Verify firewall rules
gcloud compute firewall-rules list --filter="network:dataproc-sql-network"

# 3. Check Dataproc cluster network
gcloud dataproc clusters describe CLUSTER_NAME --region=REGION

# 4. Test from Dataproc manually
gcloud compute ssh DATAPROC_MASTER_NODE -- nc -zv CLOUD_SQL_IP 5432
```

### Issue: "Permission denied"

**Solution:**
```bash
# Verify service account has necessary roles
gcloud projects get-iam-policy PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:YOUR_SA@PROJECT.iam.gserviceaccount.com"
```

## Performance Considerations

- **Execution time**: ~30-60 seconds total
  - Instance discovery: ~5 seconds
  - Job submission: ~10 seconds
  - Job execution: ~20-30 seconds
  - Job completion wait: ~10 seconds

## Common Failure Scenarios

### Scenario 1: Fresh Deployment

**Symptom:** VPC peering not yet active

**Timing:** Immediately after `terraform apply`

**Solution:** Wait 1-2 minutes for peering to propagate

### Scenario 2: Wrong Network

**Symptom:** Connection timeout

**Root cause:** Dataproc and Cloud SQL in different VPCs

**Solution:** Verify both use same VPC in Terraform config

### Scenario 3: Firewall Misconfiguration

**Symptom:** Connection refused or timeout

**Root cause:** Firewall blocking port 5432

**Solution:** Check firewall rules allow internal traffic

## Best Practices

### 1. Run After Infrastructure Changes

Always run verification after:
- Terraform apply
- Network configuration changes
- Firewall rule updates
- VPC peering modifications

### 2. Include in CI/CD

Make verification a required step:
```yaml
- name: Verify Database Connectivity
  run: ./scripts/verify_db_access.sh
  # If this fails, pipeline stops
```

### 3. Monitor Job History

Review Dataproc job logs:
```bash
gcloud dataproc jobs list --region=us-central1 --limit=10
```

### 4. Automate Retry Logic

For transient failures:
```bash
# In CI/CD
./scripts/verify_db_access.sh || (sleep 30 && ./scripts/verify_db_access.sh)
```

## Security Considerations

### What This Script Exposes

- ✅ **Safe**: Only tests TCP connectivity
- ✅ **Safe**: Doesn't transmit credentials
- ✅ **Safe**: Doesn't access database internals

### What to Protect

- 🔒 Private IP address is logged (acceptable within GCP)
- 🔒 Instance names are visible (acceptable)
- 🔒 Control access to Dataproc job submission

## Related Scripts

- [`setup_terraform_backend.sh`](./Setup_Backend_Workflow.md) - Terraform backend setup
- [`setup_db.sh`](./Setup_DB_Workflow.md) - Database schema setup
- [`generate_hospital_data.py`](./Data_Generator.md) - Test data generation

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-11-29 | Initial implementation with socket test |
| 1.1 | 2025-11-29 | Fixed jq parsing for private IP |

---

**Script Source:** [`scripts/verify_db_access.sh`](file:///home/mukuthans/Documents/Personal/gcp_emr_implementation/scripts/verify_db_access.sh)
