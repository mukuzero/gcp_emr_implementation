# Testing Hospital Data Generator Locally

This guide explains how to test the hospital data generator script locally before deploying it to production.

## Prerequisites

1. **Python 3.x** installed on your system
2. **pip** package manager
3. **Virtual environment** (recommended)

## Setup Instructions

### Step 1: Create Virtual Environment

```bash
cd /gcp_emr_implementation/scripts

# Create virtual environment
python3 -m venv data_gen_env

# Activate virtual environment
source data_gen_env/bin/activate
```

### Step 2: Install Dependencies

```bash
# Install required packages
pip install pandas faker
```

### Step 3: Run the Data Generator

```bash
# Make sure the script is executable
chmod +x generate_hospital_data.py

# Run the script
python3 generate_hospital_data.py
```

## What the Script Does

The script generates synthetic hospital data in CSV format:

1. **Hospitals** - 2 hospital record (configurable)
2. **Departments** - 20 department records (for each hospital)
3. **Providers** - 50 provider/doctor records (for each hospital)
4. **Patients** - 5,000 patient records (for each hospital)
5. **Encounters** - 10,000 encounter records (for each hospital)
6. **Transactions** - 10,000 transaction records (for each hospital)

All tables include:
- `created_at` - Timestamp of record creation
- `updated_at` - Timestamp of last update
- `deleted_at` - NULL for active records, timestamp for soft-deleted records

## Generated Files

After running the script, you'll find these CSV files in the current directory:

```
hospitals.csv
hosp1_departments.csv
hosp1_providers.csv
hosp1_patients.csv
hosp1_encounters.csv
hosp1_transactions.csv
hosp2_departments.csv
hosp2_providers.csv
hosp2_patients.csv
hosp2_encounters.csv
hosp2_transactions.csv
```

## Customizing Data Volume

Edit the configuration in `generate_hospital_data.py`:

```python
# Configuration in main() function
NUM_HOSPITALS = 2            # Change this
HOSPITAL_ID = "HOSP1"
NUM_PATIENTS = 5000          # Change this
NUM_PROVIDERS = 50           # Change this
NUM_ENCOUNTERS = 10000       # Change this
NUM_TRANSACTIONS = 10000     # Change this
```

## Understanding Soft Deletes

All generated records include soft delete support:
- `deleted_at = None` - Active record
- `deleted_at = <timestamp>` - Soft-deleted record

To "delete" a record, set `deleted_at` to current timestamp instead of removing it from the database.

## Testing Individual Functions

You can test individual data generation functions:

```python
# In Python interactive shell
from generate_hospital_data import generate_hospitals, generate_patients, generate_departments

# Generate only hospitals
generate_hospitals(num_hospitals=1)

# Generate only patients
generate_patients(num_records=100, hospital_id="TEST")

# Generate only departments
generate_departments(hospital_id="TEST")
```

## Validating Generated Data

### Check File Sizes

```bash
ls -lh hosp1_*.csv
```

### View Sample Records

```bash
# View first 10 lines of patients file
head -n 10 hosp1_patients.csv

# Count total records
wc -l hosp1_patients.csv
```

### Use pandas to inspect

```python
import pandas as pd

# Load and inspect
df = pd.read_csv("hosp1_patients.csv")
print(df.head())
print(df.info())
print(df.describe())
```

## Cleanup

### Remove Generated Files

```bash
rm hospitals.csv hosp1_*.csv
```

### Deactivate Virtual Environment

```bash
deactivate
```

### Remove Virtual Environment

```bash
rm -rf data_gen_env
```


## Troubleshooting



### Issue: "Permission denied" when running script

**Solution:** Make the script executable:
```bash
chmod +x generate_hospital_data.py
```

### Issue: Script runs slowly

**Solution:** Reduce the number of records in the configuration:
```python
NUM_PATIENTS = 1000  # Instead of 5000
NUM_ENCOUNTERS = 2000  # Instead of 10000
```

## Performance Benchmarks

On a typical development machine:

| Dataset | Records | Generation Time |
|---------|---------|-----------------|
| Hospitals | 1 | <1 second |
| Departments | 20 | <1 second |
| Providers | 50 | ~2 seconds |
| Patients | 5,000 | ~10 seconds |
| Encounters | 10,000 | ~15 seconds |
| Transactions | 10,000 | ~15 seconds |
| **Total** | **25,071** | **~43 seconds** |


**Last Updated:** 2025-11-30  
**Script Version:** 1.0
