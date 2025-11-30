# Setup Database Workflow Documentation

## Overview

The `setup_db.sh` script automates the execution of DDL (Data Definition Language) scripts on the Cloud SQL PostgreSQL instance. It uses Cloud SQL Proxy to establish a secure connection and runs the schema creation script to set up the hospital management database.

## Purpose

- **Automated Schema Setup**: Execute DDL scripts without manual intervention
- **Secure Connection**: Use Cloud SQL Proxy for authenticated, encrypted connections
- **CI/CD Integration**: Enable automated database setup in GitHub Actions
- **Idempotent Execution**: Safe to run multiple times with `CREATE TABLE IF NOT EXISTS`

## Script Location

```
scripts/setup_db.sh
```

## Prerequisites

- **Cloud SQL Proxy** installed and accessible in PATH
- **PostgreSQL Client (psql)** installed
- **DDL File** available at `./scripts/ddl.sql` (or custom path via `DDL_FILE` env var)
- **gcloud CLI** authenticated with appropriate permissions
- **Environment Variables** set (especially `DB_PASSWORD`)

## Usage

### GitHub Actions

```yaml
- name: Setup Database Schema
  env:
    GOOGLE_CREDENTIALS: ${{ secrets.GOOGLE_CREDENTIALS }}
    DB_PASSWORD: ${{ secrets.DB_PASSWORD }}
    DB_NAME: ${{ secrets.DB_NAME }}
    DB_USER: ${{ secrets.DB_USER }}
  run: |
    echo "$GOOGLE_CREDENTIALS" > gcloud-key.json
    gcloud auth activate-service-account --key-file=gcloud-key.json
    chmod +x scripts/setup_db.sh
    ./scripts/setup_db.sh
    rm gcloud-key.json
```

### Local Testing

```bash
export DB_PASSWORD="your-password"
export DB_NAME="ehmr"
export DB_USER="mukunthan"
./scripts/setup_db.sh
```

## Workflow Breakdown

### Step 1: Configuration & Environment Variables

```bash
DB_INSTANCE_NAME_PREFIX="${DB_INSTANCE_NAME_PREFIX:-low-tier-db-instance}"
DB_NAME="${DB_NAME:-ehmr}"
DB_USER="${DB_USER:-mukunthan}"
DDL_FILE="${DDL_FILE:-./scripts/ddl.sql}"
REGION="${REGION:-us-central1}"
# DB_PASSWORD should be set as environment variable
```

**What happens:**
- Sets default values for configuration variables
- Allows overriding via environment variables
- Uses parameter expansion syntax `${VAR:-default}`

**Available overrides:**
- `DB_INSTANCE_NAME_PREFIX` - Prefix for Cloud SQL instance name search
- `DB_NAME` - Target database name
- `DB_USER` - Database username
- `DDL_FILE` - Path to DDL script
- `REGION` - GCP region
- `DB_PASSWORD` - **Required** database password (no default)

### Step 2: Validate Environment Variables

```bash
if [ -z "$DB_PASSWORD" ]; then
  echo "Error: DB_PASSWORD environment variable is not set."
  echo "Please set DB_PASSWORD before running this script."
  exit 1
fi
```

**What happens:**
- Checks if `DB_PASSWORD` is set
- Exits with error if missing
- Prevents script from running without authentication

**Why this matters:**
- Security: Avoids hardcoding passwords in script
- CI/CD: Forces explicit secret configuration
- Error prevention: Fails early instead of during connection attempt

### Step 3: Validate DDL File Exists

```bash
if [ ! -f "$DDL_FILE" ]; then
  echo "Error: DDL file not found at: $DDL_FILE"
  echo "Please ensure ddl.sql exists in the current directory."
  exit 1
fi
```

**What happens:**
- Checks if DDL file exists at specified path
- Exits early if file is missing
- Provides clear error message

**Example error:**
```
Error: DDL file not found at: ./scripts/ddl.sql
Please ensure ddl.sql exists in the current directory.
```

### Step 4: Find Cloud SQL Instance

```bash
INSTANCE_NAME=$(gcloud sql instances list --format="value(name)" --filter="name~^${DB_INSTANCE_NAME_PREFIX}")

if [ -z "$INSTANCE_NAME" ]; then
  echo "Error: Cloud SQL instance starting with '$DB_INSTANCE_NAME_PREFIX' not found."
  exit 1
fi
```

**What happens:**
- Uses `gcloud sql instances list` to search for instances
- Filters by instance name prefix using regex match (`~^`)
- Extracts only the name field using `--format="value(name)"`
- Stores instance name in variable

**Example:**
```bash
# Finds: low-tier-db-instance-ac543943
# Stores: INSTANCE_NAME="low-tier-db-instance-ac543943"
```

**Why dynamic discovery:**
- Terraform appends random suffix to instance names
- Script adapts to different environments automatically
- No hardcoding of instance names

### Step 5: Get Private IP Address

```bash
PRIVATE_IP=$(gcloud sql instances describe "$INSTANCE_NAME" --format="json" | jq -r '.ipAddresses[] | select(.type == "PRIVATE") | .ipAddress')

if [ -z "$PRIVATE_IP" ]; then
  echo "Error: Could not find private IP for instance $INSTANCE_NAME"
  exit 1
fi
```

**What happens:**
- Fetches instance metadata in JSON format
- Uses `jq` to parse JSON and extract private IP
- Filters for IP addresses with type "PRIVATE"
- Validates that private IP was found

**jq pipeline explanation:**
```bash
.ipAddresses[]                    # Iterate through IP addresses
| select(.type == "PRIVATE")      # Filter for private IP
| .ipAddress                       # Extract IP address value
```

**Example output:**
```
Private IP: 10.219.0.3
```

### Step 6: Start Cloud SQL Proxy

```bash
cloud_sql_proxy --address 127.0.0.1 --port 5432 "$INSTANCE_NAME" &
PROXY_PID=$!
```

**What happens:**
- Starts Cloud SQL Proxy in background (`&`)
- Binds to localhost (`127.0.0.1`) on port `5432`
- Captures process ID in `PROXY_PID` for later cleanup

**Cloud SQL Proxy details:**
- **Connection**: Connects to Cloud SQL using IAM authentication
- **Encryption**: TLS-encrypted tunnel
- **Local access**: Makes Cloud SQL accessible at `localhost:5432`

### Step 7: Wait for Proxy to Initialize

```bash
sleep 5
```

**What happens:**
- Waits 5 seconds for proxy to establish connection
- Ensures proxy is ready before attempting database connection

**Why necessary:**
- Proxy needs time to authenticate and establish tunnel
- Immediate connection attempts may fail
- Simple but effective approach for automation

### Step 8: Execute DDL Script

```bash
export PGPASSWORD="$DB_PASSWORD"

if psql -h 127.0.0.1 -p 5432 -U "$DB_USER" -d "$DB_NAME" -f "$DDL_FILE"; then
  echo "DDL executed successfully!"
else
  echo "Error: Failed to execute DDL"
  kill $PROXY_PID 2>/dev/null || true
  exit 1
fi
```

**What happens:**
- Sets `PGPASSWORD` environment variable for psql authentication
- Runs `psql` command with DDL file
- Checks exit code for success/failure
- Cleans up proxy on failure

**psql command breakdown:**
- `-h 127.0.0.1` - Connect to localhost (proxy)
- `-p 5432` - Use port 5432
- `-U "$DB_USER"` - Username (e.g., mukunthan)
- `-d "$DB_NAME"` - Database name (e.g., ehmr)
- `-f "$DDL_FILE"` - Execute SQL from file

**Success output:**
```
================================================================
DDL executed successfully!
================================================================
```

### Step 9: Cleanup

```bash
kill $PROXY_PID 2>/dev/null || true
unset PGPASSWORD
```

**What happens:**
- Stops Cloud SQL Proxy process
- Removes password from environment
- Suppresses errors if proxy already exited

**Security note:**
- `unset PGPASSWORD` ensures password doesn't persist in environment
- `2>/dev/null` suppresses kill errors if process already terminated
- `|| true` prevents script failure from cleanup errors

## Complete Workflow Diagram

```
┌─────────────────────────────────────┐
│   User/CI runs setup_db.sh         │
│   with env vars set                 │
└─────────────┬───────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│   Validate DB_PASSWORD is Set      │
└─────────────┬───────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│   Check DDL File Exists             │
│   Default: ./scripts/ddl.sql        │
└─────────────┬───────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│   Find Cloud SQL Instance           │
│   gcloud sql instances list         │
└─────────────┬───────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│   Get Private IP Address            │
│   Parse with jq                     │
└─────────────┬───────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│   Start Cloud SQL Proxy             │
│   Bind to localhost:5432            │
└─────────────┬───────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│   Wait 5 Seconds                    │
│   Allow proxy to initialize         │
└─────────────┬───────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│   Execute DDL with psql             │
│   CREATE tables, indexes, etc.      │
└─────────────┬───────────────────────┘
              │
         ┌────┴────┐
         │         │
    Success    Failure
         │         │
         │         ▼
         │    ┌─────────────────────────┐
         │    │   Kill Proxy             │
         │    │   Exit with code 1       │
         │    └─────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│   Kill Cloud SQL Proxy              │
│   Unset PGPASSWORD                  │
└─────────────┬───────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│   Success - Database Ready          │
│   Return exit code 0                │
└─────────────────────────────────────┘
```

## Integration with DDL Schema

The script executes `scripts/ddl.sql` which creates:

1. **hospitals** - Hospital information
2. **departments** - Departments within hospitals
3. **providers** - Healthcare providers
4. **patients** - Patient records
5. **encounters** - Patient-provider encounters
6. **transactions** - Financial transactions

All tables include:
- `created_at` - Timestamp of creation
- `updated_at` - Last modification timestamp
- `deleted_at` - Soft delete marker (NULL = active)

## Security Considerations

### 1. Password Management
- **Never hardcode** passwords in the script
- Use environment variables from secrets management
- Unset `PGPASSWORD` after use

### 2. Cloud SQL Proxy Benefits
- **No public IP** needed for Cloud SQL
- **IAM authentication** instead of IP whitelisting
- **TLS encryption** for data in transit
- **Automatic credential rotation** with service accounts

### 3. Service Account Permissions

Required roles:
- `roles/cloudsql.client` - Connect via Cloud SQL Proxy
- `roles/cloudsql.viewer` - Describe instances

## Error Handling

### Automatic Cleanup

The script includes cleanup on failure:
```bash
if psql ...; then
  echo "Success"
else
  kill $PROXY_PID 2>/dev/null || true
  exit 1
fi
```

### Common Failure Points

1. **Missing password** → Fails at Step 2
2. **Missing DDL file** → Fails at Step 3
3. **Instance not found** → Fails at Step 4
4. **No private IP** → Fails at Step 5
5. **psql connection fails** → Fails at Step 8

## Troubleshooting

### Issue: "DB_PASSWORD environment variable is not set"

**Solution:**
```bash
export DB_PASSWORD="your-actual-password"
./scripts/setup_db.sh
```

### Issue: "DDL file not found"

**Solution:**
```bash
# Specify custom DDL path
export DDL_FILE="/path/to/custom-ddl.sql"
./scripts/setup_db.sh
```

### Issue: "Cloud SQL instance not found"

**Solution:**
```bash
# Check what instances exist
gcloud sql instances list

# Override the prefix if needed
export DB_INSTANCE_NAME_PREFIX="your-instance-prefix"
./scripts/setup_db.sh
```

### Issue: "cloud_sql_proxy: command not found"

**Solution:**
```bash
# Install Cloud SQL Proxy
wget https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -O cloud_sql_proxy
chmod +x cloud_sql_proxy
sudo mv cloud_sql_proxy /usr/local/bin/
```

### Issue: "psql: command not found"

**Solution:**
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y postgresql-client

# macOS
brew install postgresql
```

### Issue: Connection timeout

**Possible causes:**
- Proxy not fully initialized (increase sleep time)
- Network connectivity issues
- Firewall blocking proxy
- Service account lacks permissions

**Solution:**
```bash
# Increase wait time in script (edit setup_db.sh)
sleep 10  # Instead of sleep 5
```

## Best Practices

### 1. Idempotent DDL

Always use `CREATE TABLE IF NOT EXISTS`:
```sql
CREATE TABLE IF NOT EXISTS patients (
    -- columns
);
```

### 2. Environment Configuration

Create a `.env` file for local testing:
```bash
# .env
export DB_PASSWORD="local-password"
export DB_NAME="ehmr"
export DB_USER="mukunthan"
export DB_INSTANCE_NAME_PREFIX="local-db-instance"
```

Load before running:
```bash
source .env
./scripts/setup_db.sh
```

### 3. CI/CD Secrets

Always use secrets, never commit:
```yaml
env:
  DB_PASSWORD: ${{ secrets.DB_PASSWORD }}  # ✅ Good
  # DB_PASSWORD: "hardcoded-password"     # ❌ Never do this
```

## Performance Considerations

- **Proxy startup**: ~5 seconds overhead
- **DDL execution**: Depends on complexity (typically <10 seconds for schema creation)
- **Total runtime**: Usually <20 seconds

## Related Scripts

- [`setup_terraform_backend.sh`](./Setup_Backend_Workflow.md) - Terraform backend setup
- [`verify_db_access.sh`](../scripts/verify_db_access.sh) - Database connectivity test
- [`generate_hospital_data.py`](./Data_Generator.md) - Generate test data

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-11-30 | Initial documentation |

---

**Script Source:** [`scripts/setup_db.sh`](file:///home/mukuthans/Documents/Personal/gcp_emr_implementation/scripts/setup_db.sh)  
**DDL Source:** [`scripts/ddl.sql`](file:///home/mukuthans/Documents/Personal/gcp_emr_implementation/scripts/ddl.sql)
