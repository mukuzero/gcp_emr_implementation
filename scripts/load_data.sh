#!/bin/bash

set -e

# Configuration - can be overridden by environment variables
DB_INSTANCE_NAME_PREFIX="${DB_INSTANCE_NAME_PREFIX:-low-tier-db-instance}"

# Required environment variables
# REGION - GCP region
# DB_NAME - Database name
# DB_USER - Database username
# DB_PASSWORD - Database password

echo "================================================================"
echo "Hospital Data Loading Script"
echo "================================================================"

# Validate required environment variables
if [ -z "$REGION" ]; then
  echo "Error: REGION environment variable is not set."
  exit 1
fi

if [ -z "$DB_PASSWORD" ]; then
  echo "Error: DB_PASSWORD environment variable is not set."
  exit 1
fi

if [ -z "$DB_NAME" ]; then
  echo "Error: DB_NAME environment variable is not set."
  exit 1
fi

if [ -z "$DB_USER" ]; then
  echo "Error: DB_USER environment variable is not set."
  exit 1
fi

# Find the Cloud SQL instance
if [ -n "$DB_CONNECTION_NAME" ]; then
  echo "Using connection name from environment: $DB_CONNECTION_NAME"
  INSTANCE_NAME="$DB_CONNECTION_NAME"
  
  if [ -z "$INSTANCE_NAME" ]; then
    echo "Error: Cloud SQL instance starting with '$DB_INSTANCE_NAME_PREFIX' not found."
    exit 1
  fi
fi

echo "Found instance: $INSTANCE_NAME"

# Start Cloud SQL Proxy
echo "Starting Cloud SQL Proxy..."
cloud_sql_proxy --address 127.0.0.1 --port 5432 "$INSTANCE_NAME" &
PROXY_PID=$!

# Wait for proxy to be ready
echo "Waiting for Cloud SQL Proxy to be ready..."
sleep 5

# Create a temporary directory for data generation
DATA_DIR=$(mktemp -d)
echo "Created temporary directory for data generation: $DATA_DIR"

# Ensure cleanup happens on exit
cleanup() {
  echo "Cleaning up..."
  kill $PROXY_PID 2>/dev/null || true
  rm -rf "$DATA_DIR"
  echo "Cleanup complete."
}
trap cleanup EXIT

# Generate Data
echo "Generating synthetic data..."
# Get the absolute path of the generator script
GENERATOR_SCRIPT="$(pwd)/scripts/generate_hospital_data.py"

if [ ! -f "$GENERATOR_SCRIPT" ]; then
    echo "Error: Generator script not found at $GENERATOR_SCRIPT"
    exit 1
fi

# Run generator in the temp directory
cd "$DATA_DIR"
python3 "$GENERATOR_SCRIPT"

echo "Data generation complete. Files created in $DATA_DIR"
ls -l "$DATA_DIR"

# Load Data
echo "Loading data into Cloud SQL..."
export PGPASSWORD="$DB_PASSWORD"
DB_HOST="127.0.0.1"
DB_PORT="5432"

# Function to load a table
load_table() {
    local table_name=$1
    local file_name=$2
    local columns=$3
    
    echo "Loading table: $table_name from $file_name..."
    
    if [ ! -f "$file_name" ]; then
        echo "Warning: File $file_name not found. Skipping $table_name."
        return
    fi
    
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "\copy $table_name($columns) FROM '$file_name' DELIMITER ',' CSV HEADER;"
}

# Define columns for each table (based on ddl.sql and generate_hospital_data.py)
# Note: The CSV headers in the python script match the column names in the DB, 
# so we can technically omit the column list if the CSV order matches the DB order exactly.
# However, specifying columns is safer.

# Load Order: Hospitals -> Departments -> Providers -> Patients -> Encounters -> Transactions

# 1. Hospitals
# CSV: hospitalID, Name, Address, PhoneNumber, created_at, updated_at, deleted_at
load_table "hospitals" "hospitals.csv" "hospitalID, Name, Address, PhoneNumber, created_at, updated_at, deleted_at"

# 2. Departments
# CSV: hospitalID, DeptID, Name, created_at, updated_at, deleted_at
# Note: The generator creates multiple department files (hosp1_departments.csv, hosp2_departments.csv)
for f in *_departments.csv; do
    load_table "departments" "$f" "hospitalID, DeptID, Name, created_at, updated_at, deleted_at"
done

# 3. Providers
# CSV: hospitalID, ProviderID, FirstName, LastName, Specialization, DeptID, NPI, created_at, updated_at, deleted_at
for f in *_providers.csv; do
    load_table "providers" "$f" "hospitalID, ProviderID, FirstName, LastName, Specialization, DeptID, NPI, created_at, updated_at, deleted_at"
done

# 4. Patients
# CSV: hospitalID, PatientID, FirstName, LastName, MiddleName, SSN, PhoneNumber, Gender, DOB, Address, ModifiedDate, created_at, updated_at, deleted_at
for f in *_patients.csv; do
    load_table "patients" "$f" "hospitalID, PatientID, FirstName, LastName, MiddleName, SSN, PhoneNumber, Gender, DOB, Address, ModifiedDate, created_at, updated_at, deleted_at"
done

# 5. Encounters
# CSV: hospitalID, EncounterID, PatientID, EncounterDate, EncounterType, ProviderID, DepartmentID, ProcedureCode, InsertedDate, ModifiedDate, created_at, updated_at, deleted_at
for f in *_encounters.csv; do
    load_table "encounters" "$f" "hospitalID, EncounterID, PatientID, EncounterDate, EncounterType, ProviderID, DepartmentID, ProcedureCode, InsertedDate, ModifiedDate, created_at, updated_at, deleted_at"
done

# 6. Transactions
# CSV: hospitalID, TransactionID, EncounterID, PatientID, ProviderID, DeptID, VisitDate, ServiceDate, PaidDate, VisitType, Amount, AmountType, PaidAmount, ClaimID, PayorID, ProcedureCode, ICDCode, LineOfBusiness, MedicaidID, MedicareID, InsertDate, ModifiedDate, created_at, updated_at, deleted_at
for f in *_transactions.csv; do
    load_table "transactions" "$f" "hospitalID, TransactionID, EncounterID, PatientID, ProviderID, DeptID, VisitDate, ServiceDate, PaidDate, VisitType, Amount, AmountType, PaidAmount, ClaimID, PayorID, ProcedureCode, ICDCode, LineOfBusiness, MedicaidID, MedicareID, InsertDate, ModifiedDate, created_at, updated_at, deleted_at"
done

echo "================================================================"
echo "Data Loading Complete!"
echo "================================================================"

# Verification
echo "Verifying data counts..."

verify_count() {
    local table_name=$1
    local count=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM $table_name;" | xargs)
    echo "Table: $table_name, Count: $count"
}

verify_count "hospitals"
verify_count "departments"
verify_count "providers"
verify_count "patients"
verify_count "encounters"
verify_count "transactions"

echo "================================================================"
