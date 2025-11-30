# Setup Backend Workflow Documentation

## Overview

The `setup_backend.sh` script automates the creation and configuration of the Google Cloud Storage (GCS) bucket used as the Terraform remote backend. This ensures that Terraform state files are stored securely and can be shared across team members and CI/CD pipelines.

## Purpose

- **Centralized State Management**: Stores Terraform state in GCS instead of locally
- **Team Collaboration**: Enables multiple developers to work with the same infrastructure
- **State Locking**: Prevents concurrent modifications through GCS versioning
- **CI/CD Integration**: Allows GitHub Actions to manage infrastructure state

## Script Location

```
scripts/setup_backend.sh
```

## Usage

### Command Line

```bash
./scripts/setup_backend.sh <BUCKET_NAME> <REGION>
```

### GitHub Actions

```yaml
- name: Setup Backend Bucket
  env:
    GOOGLE_CREDENTIALS: ${{ secrets.GOOGLE_CREDENTIALS }}
  run: |
    echo "$GOOGLE_CREDENTIALS" > gcloud-key.json
    gcloud auth activate-service-account --key-file=gcloud-key.json
    ../scripts/setup_backend.sh "${{ secrets.TF_BACKEND_BUCKET }}" "${{ secrets.GCP_REGION }}"
    rm gcloud-key.json
```

## Workflow Breakdown

### Step 1: Input Validation

```bash
BUCKET_NAME=$1
REGION=$2

if [ -z "$BUCKET_NAME" ] || [ -z "$REGION" ]; then
  echo "Usage: $0 <BUCKET_NAME> <REGION>"
  exit 1
fi
```

**What happens:**
- Accepts two command-line arguments: bucket name and region
- Validates that both arguments are provided
- Exits with error code 1 if validation fails

**Example:**
```bash
./setup_backend.sh my-tf-state-12345 us-central1
```

### Step 2: Check Bucket Existence

```bash
echo "Checking if bucket gs://$BUCKET_NAME exists..."

if ! gcloud storage buckets describe gs://$BUCKET_NAME > /dev/null 2>&1; then
  # Bucket does not exist
else
  # Bucket already exists
fi
```

**What happens:**
- Uses `gcloud storage buckets describe` to check if bucket exists
- Suppresses output (`> /dev/null 2>&1`) to keep logs clean
- Proceeds to Step 3 if bucket doesn't exist
- Proceeds to Step 4 if bucket already exists

**gcloud command details:**
- `gcloud storage buckets describe gs://$BUCKET_NAME` - Fetches bucket metadata
- Exit code `0` = bucket exists
- Exit code `1` = bucket doesn't exist

### Step 3: Create Bucket (If Needed)

```bash
echo "Bucket gs://$BUCKET_NAME does not exist. Creating it..."
gcloud storage buckets create gs://$BUCKET_NAME --location=$REGION
```

**What happens:**
- Creates a new GCS bucket with the specified name
- Sets the bucket location to the provided region
- Uses standard storage class (cost-effective for Terraform state)

**Example output:**
```
Creating gs://my-tf-state-12345/...
```

### Step 4: Enable Versioning

```bash
echo "Enabling versioning on gs://$BUCKET_NAME..."
gcloud storage buckets update gs://$BUCKET_NAME --versioning
```

**What happens:**
- Enables object versioning on the bucket
- Protects against accidental state file deletions
- Allows rollback to previous state versions if needed

**Why versioning matters:**
- **Recovery**: Restore previous state if corruption occurs
- **Audit Trail**: Track changes to infrastructure state over time
- **Safety Net**: Prevent data loss from accidental deletions

### Step 5: Success Confirmation

```bash
echo "Bucket created successfully."
```

**Or if bucket already existed:**

```bash
echo "Bucket gs://$BUCKET_NAME already exists."
```

**What happens:**
- Confirms the operation completed successfully
- Script exits with code 0 (success)

## Error Handling

The script uses `set -e` at the beginning, which means:
- Any command that fails will immediately exit the script
- Provides fail-fast behavior for CI/CD pipelines
- Prevents partial/incomplete backend setup

## Idempotency

The script is **idempotent**, meaning:
- Running it multiple times produces the same result
- Safe to run in CI/CD pipelines on every workflow execution
- Won't fail if the bucket already exists

## Complete Workflow Diagram

```
┌─────────────────────────────────────┐
│   User/CI runs setup_backend.sh    │
│   with BUCKET_NAME and REGION       │
└─────────────┬───────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│   Validate Input Arguments          │
│   - Check BUCKET_NAME provided      │
│   - Check REGION provided            │
└─────────────┬───────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│   Check if Bucket Exists            │
│   gcloud storage buckets describe   │
└─────────────┬───────────────────────┘
              │
         ┌────┴────┐
         │         │
    Exists    Doesn't Exist
         │         │
         │         ▼
         │    ┌─────────────────────────┐
         │    │   Create Bucket          │
         │    │   at specified region    │
         │    └──────────┬──────────────┘
         │               │
         └───────┬───────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│   Enable Versioning                 │
│   gcloud storage buckets update     │
└─────────────┬───────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│   Success - Bucket Ready            │
│   Return exit code 0                │
└─────────────────────────────────────┘
```

## Integration Points

### 1. GitHub Actions Workflow

**File:** `.github/workflows/terraform.yml`

The script runs as part of the "Setup Backend Bucket" step:

```yaml
- name: Setup Backend Bucket
  env:
    GOOGLE_CREDENTIALS: ${{ secrets.GOOGLE_CREDENTIALS }}
  run: |
    echo "$GOOGLE_CREDENTIALS" > gcloud-key.json
    gcloud auth activate-service-account --key-file=gcloud-key.json
    ../scripts/setup_backend.sh "${{ secrets.TF_BACKEND_BUCKET }}" "${{ secrets.GCP_REGION }}"
    rm gcloud-key.json
```

**When it runs:**
- On every pull request to master
- Before `terraform init`
- Ensures backend is ready before Terraform operations

### 2. Terraform Backend Configuration

**File:** `terraform/main.tf`

```hcl
terraform {
  backend "gcs" {
    bucket = "my-tf-state-12345"  # Set via -backend-config
    prefix = "terraform/state"
  }
}
```

The bucket created by this script is referenced during `terraform init`:

```bash
terraform init -backend-config="bucket=${{ secrets.TF_BACKEND_BUCKET }}"
```

## Required Permissions

The service account running this script needs:

- `storage.buckets.create` - Create new buckets
- `storage.buckets.get` - Check bucket existence
- `storage.buckets.update` - Enable versioning

**Predefined role:** `roles/storage.admin` or custom role with above permissions

## Environment Variables

No environment variables are directly used by the script, but it expects:

1. **gcloud CLI** to be authenticated
2. **Active GCP project** to be set

## Security Considerations

### 1. Bucket Naming
- Use unique, unpredictable bucket names
- Don't include sensitive information in bucket name
- Example: `my-tf-state-12345` (with random suffix)

### 2. Access Control
- Bucket should have restricted IAM policies
- Only service accounts and admins should have access
- Enable uniform bucket-level access

### 3. Encryption
- GCS encrypts data at rest by default
- Consider customer-managed encryption keys (CMEK) for sensitive environments

## Troubleshooting

### Issue: "Bucket already exists but is owned by another project"

**Solution:**
```bash
# Choose a different bucket name
./setup_backend.sh my-tf-state-NEW-NAME us-central1
```

### Issue: "Permission denied"

**Solution:**
```bash
# Verify authentication
gcloud auth list

# Verify project is set
gcloud config get-value project

# Check IAM permissions
gcloud projects get-iam-policy <PROJECT_ID>
```

### Issue: "Invalid bucket name"

**Error:** Bucket names must follow DNS naming conventions

**Solution:**
- Use lowercase letters, numbers, hyphens, and underscores only
- Must be 3-63 characters
- Cannot start/end with hyphen

## Best Practices

1. **Bucket Naming Convention**
   ```
   <org>-<env>-tf-state-<random>
   example: mycompany-prod-tf-state-a1b2c3
   ```

2. **Regional Consistency**
   - Use same region as your infrastructure
   - Reduces latency during Terraform operations
   - May reduce egress costs

3. **Backup Strategy**
   - Versioning is enabled automatically
   - Consider periodic backups to another location
   - Document recovery procedures

4. **Monitoring**
   - Set up alerts for bucket access
   - Monitor object count and size
   - Track version count to manage costs

## Related Documentation

- [Terraform GCS Backend](https://developer.hashicorp.com/terraform/language/settings/backends/gcs)
- [GCS Bucket Versioning](https://cloud.google.com/storage/docs/object-versioning)
- [GitHub Actions Workflow](../docs/CI_CD_Pipeline.md)

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-11-30 | Initial documentation |

---

**Script Source:** [`scripts/setup_backend.sh`](file:///home/mukuthans/Documents/Personal/gcp_emr_implementation/scripts/setup_backend.sh)
