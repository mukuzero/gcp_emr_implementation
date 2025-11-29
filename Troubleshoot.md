# Troubleshooting Terraform Destroy Failure

## Issue Summary

When attempting to destroy the infrastructure using `terraform destroy`, the operation failed due to a stuck Service Networking connection dependency. This document provides a detailed account of the issue and its resolution.

---

## Error Encountered

### Initial Destroy Attempt

**Command:**
```bash
terraform destroy -var="project_id=stable-splicer-408606" \
                 -var="db_password=********" \
                 -var="db_name=ehmr" \
                 -var="db_user=mukunthan" \
                 -var="region=us-central1"
```

**Errors:**

1. **Service Networking Connection Error:**
```
Error: Unable to remove Service Networking Connection, err: Error waiting for Delete Service Networking Connection: Error code 9, message: Failed to delete connection; Producer services (e.g. CloudSQL, Cloud Memstore, etc.) are still using this connection.
```

2. **State Upload Failure:**
```
Error: Failed to upload state to gs://my-tf-state-12345/terraform/state/default.tfstate: Post "https://storage.googleapis.com/upload/storage/v1/b/my-tf-state-12345/o?...": http2: client connection lost
```

---

## Root Cause Analysis

### What Happened?

The `terraform destroy` operation encountered a **race condition** during resource deletion:

1. **Successful Deletions:**
   - Cloud SQL instance (`low-tier-db-instance-ac543943`) was destroyed
   - Dataproc cluster was destroyed
   - Subnet was destroyed

2. **Failed Deletions:**
   - Service Networking Connection (`private_vpc_connection`) failed to delete
   - This blocked deletion of:
     - Private IP Address (`private-ip-address`)
     - VPC Network (`dataproc-sql-network`)

### Why Did It Fail?

**Service Networking Dependency Issue:**
- GCP's Service Networking service maintains a VPC peering connection between your VPC and Google's managed service network
- Even though the Cloud SQL instance was deleted, the peering connection remained active
- GCP refused to delete the connection, claiming producer services were still using it
- This created a circular dependency where Terraform couldn't proceed

**State Upload Failure:**
- The HTTP/2 connection to GCS was lost during state upload
- This was likely a transient network issue
- The state lock was properly released

---

## Resolution Steps

### Step 1: Verify Cloud SQL Deletion

**Command:**
```bash
gcloud sql instances list --project=stable-splicer-408606
```

**Result:**
```
Listed 0 items.
```

✅ **Confirmed:** Cloud SQL instance was successfully deleted.

---

### Step 2: Check VPC Peering Status

**Command:**
```bash
gcloud compute networks peerings list --network=dataproc-sql-network --project=stable-splicer-408606
```

**Result:**
```
NAME                              NETWORK               PEER_PROJECT           PEER_NETWORK       STATE
servicenetworking-googleapis-com  dataproc-sql-network  hdb6e524bb04fd3d2p-tp  servicenetworking  ACTIVE
```

❌ **Issue Identified:** VPC peering was still **ACTIVE** despite Cloud SQL deletion.

---

### Step 3: Attempt Manual Service Networking Deletion

**Command:**
```bash
gcloud services vpc-peerings delete --network=dataproc-sql-network \
                                     --service=servicenetworking.googleapis.com \
                                     --project=stable-splicer-408606
```

**Result:**
```
ERROR: ... FLOW_SN_DC_RESOURCE_PREVENTING_DELETE_CONNECTION
```

❌ **Failed:** GCP still believes resources are using the connection.

---

### Step 4: Attempt VPC Network Deletion

**Command:**
```bash
gcloud compute networks delete dataproc-sql-network --project=stable-splicer-408606 --quiet
```

**Result:**
```
ERROR: The network resource 'projects/stable-splicer-408606/global/networks/dataproc-sql-network' 
is already being used by 'projects/stable-splicer-408606/global/addresses/private-ip-address'
```

❌ **Failed:** VPC is being used by the global private IP address.

---

### Step 5: Delete Private IP Address (SOLUTION)

**Command:**
```bash
gcloud compute addresses delete private-ip-address --global --project=stable-splicer-408606 --quiet
```

**Result:**
```
Deleted [https://www.googleapis.com/compute/v1/projects/stable-splicer-408606/global/addresses/private-ip-address].
```

✅ **Success:** Private IP address was deleted.

---

### Step 6: Delete VPC Network

**Command:**
```bash
gcloud compute networks delete dataproc-sql-network --project=stable-splicer-408606 --quiet
```

**Result:**
```
Deleted [https://www.googleapis.com/compute/v1/projects/stable-splicer-408606/global/networks/dataproc-sql-network].
```

✅ **Success:** VPC network was deleted.

---

### Step 7: Final Terraform Destroy

**Command:**
```bash
terraform destroy -var="project_id=stable-splicer-408606" \
                 -var="db_password=********" \
                 -var="db_name=ehmr" \
                 -var="db_user=mukunthan" \
                 -var="region=us-central1" \
                 -auto-approve
```

**Result:**
```
No changes. No objects need to be destroyed.

Either you have not created any objects yet or the existing objects were already deleted outside of Terraform.

Destroy complete! Resources: 0 destroyed.
```

✅ **Success:** All resources confirmed destroyed, Terraform state is clean.

---

## Lessons Learned

### 1. Resource Deletion Order Matters

GCP Service Networking connections have strict dependency requirements:
- Private IP addresses must be deleted **before** the VPC network
- VPC network must be deleted **before** the service networking connection can be fully removed

### 2. Race Conditions in Terraform Destroy

Terraform attempted to delete the Service Networking connection while the private IP address still existed, creating a deadlock.

### 3. Manual Intervention Sometimes Required

When Terraform's dependency graph doesn't account for GCP-specific timing issues, manual resource deletion via `gcloud` may be necessary.

---

## Prevention Strategies

### Option 1: Add Explicit Dependencies

Update `terraform/main.tf` to make dependencies more explicit:

```hcl
resource "google_compute_global_address" "private_ip_address" {
  # ... existing configuration ...
  
  lifecycle {
    prevent_destroy = false
  }
}

resource "google_compute_network" "vpc_network" {
  # ... existing configuration ...
  
  depends_on = [google_compute_global_address.private_ip_address]
}
```

### Option 2: Use Terraform's `-refresh=false`

If encountering state inconsistencies:
```bash
terraform destroy -refresh=false -auto-approve
```

### Option 3: Retry with Delay

Sometimes GCP needs time to propagate deletions:
```bash
terraform destroy -auto-approve
# If it fails, wait 30-60 seconds
sleep 60
terraform destroy -auto-approve
```

---

## Quick Reference: Cleanup Commands

If you encounter the same issue in the future, use this sequence:

```bash
# 1. Verify Cloud SQL is deleted
gcloud sql instances list --project=YOUR_PROJECT_ID

# 2. Delete private IP address
gcloud compute addresses delete private-ip-address --global --project=YOUR_PROJECT_ID --quiet

# 3. Delete VPC network
gcloud compute networks delete dataproc-sql-network --project=YOUR_PROJECT_ID --quiet

# 4. Run terraform destroy to sync state
terraform destroy -auto-approve
```

---

## Related Resources

- [GCP Service Networking Documentation](https://cloud.google.com/vpc/docs/configure-private-services-access)
- [Terraform Google Provider - Service Networking](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_networking_connection)
- [GCP VPC Network Peering](https://cloud.google.com/vpc/docs/vpc-peering)

---

## Issue Status

**Status:** ✅ Resolved  
**Date:** 2025-11-29  
**Resolution Time:** ~10 minutes (manual intervention)  
**Resources Affected:** 3 (Private IP Address, VPC Network, Service Networking Connection)
