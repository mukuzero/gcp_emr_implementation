#!/usr/bin/env python3

"""
Hospital Data Generator using Faker
Generates synthetic hospital data including hospitals, patients, encounters, transactions, 
departments, and providers for testing purposes.
"""

import pandas as pd
from faker import Faker
import random
from datetime import datetime

# Initialize Faker
fake = Faker()
Faker.seed(42)  # For reproducibility

def generate_hospitals(num_hospitals=1):
    """Generate hospital records"""
    print(f"Generating {num_hospitals} hospital records...")
    
    hospital_names = [
        "General", "Memorial", "Regional", "Community", "University",
        "Medical Center", "St. Mary's", "Sacred Heart", "City", "County"
    ]
    
    data = {
        "hospitalID": [f"HOSP{str(i)}" for i in range(1, num_hospitals + 1)],
        "Name": [f"{random.choice(hospital_names)} Hospital {i}" for i in range(1, num_hospitals + 1)],
        "Address": [fake.address().replace('\n', ', ') for _ in range(num_hospitals)],
        "PhoneNumber": [fake.phone_number() for _ in range(num_hospitals)],
        "created_at": [datetime.now()] * num_hospitals,
        "updated_at": [datetime.now()] * num_hospitals,
        "deleted_at": [None] * num_hospitals
    }
    
    df = pd.DataFrame(data)
    filename = "hospitals.csv"
    df.to_csv(filename, index=False)
    print(f"Saved {filename}")
    return df

def generate_patients(num_records=50000, hospital_id="HOSP1"):
    """Generate patient records"""
    print(f"Generating {num_records} patient records for {hospital_id}...")
    
    data = {
        "hospitalID": [hospital_id] * num_records,
        "PatientID": [f"{hospital_id}-{str(i).zfill(6)}" for i in range(1, num_records + 1)],
        "FirstName": [fake.first_name() for _ in range(num_records)],
        "LastName": [fake.last_name() for _ in range(num_records)],
        "MiddleName": [fake.random_letter().upper() for _ in range(num_records)],
        "SSN": [fake.ssn() for _ in range(num_records)],
        "PhoneNumber": [fake.phone_number() for _ in range(num_records)],
        "Gender": [random.choice(["Male", "Female"]) for _ in range(num_records)],
        "DOB": [fake.date_of_birth(minimum_age=0, maximum_age=100) for _ in range(num_records)],
        "Address": [fake.address().replace('\n', ', ') for _ in range(num_records)],
        "ModifiedDate": [fake.date_this_decade(before_today=True, after_today=False) for _ in range(num_records)],
        "created_at": [datetime.now()] * num_records,
        "updated_at": [datetime.now()] * num_records,
        "deleted_at": [None] * num_records
    }
    
    df = pd.DataFrame(data)
    filename = f"{hospital_id.lower()}_patients.csv"
    df.to_csv(filename, index=False)
    print(f"Saved {filename}")
    return df

def generate_departments(hospital_id="HOSP1"):
    """Generate department records"""
    print(f"Generating departments for {hospital_id}...")
    
    departments_list = [
        "Emergency", "Cardiology", "Neurology", "Oncology", "Pediatrics", 
        "Orthopedics", "Dermatology", "Gastroenterology", "Urology", 
        "Radiology", "Anesthesiology", "Pathology", "Surgery", 
        "Pulmonology", "Nephrology", "Ophthalmology", "Gynecology", 
        "Psychiatry", "Endocrinology", "Rheumatology"
    ]
    
    data = {
        "hospitalID": [hospital_id] * len(departments_list),
        "DeptID": [f"DEPT{str(i).zfill(3)}" for i in range(1, len(departments_list) + 1)],
        "Name": departments_list,
        "created_at": [datetime.now()] * len(departments_list),
        "updated_at": [datetime.now()] * len(departments_list),
        "deleted_at": [None] * len(departments_list)
    }
    
    df = pd.DataFrame(data)
    filename = f"{hospital_id.lower()}_departments.csv"
    df.to_csv(filename, index=False)
    print(f"Saved {filename}")
    return df

def generate_providers(num_providers=50, hospital_id="HOSP1"):
    """Generate provider records"""
    print(f"Generating {num_providers} provider records for {hospital_id}...")
    
    specializations = [
        "Cardiology", "Neurology", "Orthopedics", "General Surgery", 
        "Pediatrics", "Radiology", "Dermatology", "Oncology", 
        "Anesthesiology", "Emergency Medicine", "Psychiatry"
    ]
    departments = [f"DEPT{str(i).zfill(3)}" for i in range(1, 21)]
    
    data = {
        "hospitalID": [hospital_id] * num_providers,
        "ProviderID": [f"PROV{str(i).zfill(4)}" for i in range(1, num_providers + 1)],
        "FirstName": [fake.first_name() for _ in range(num_providers)],
        "LastName": [fake.last_name() for _ in range(num_providers)],
        "Specialization": [random.choice(specializations) for _ in range(num_providers)],
        "DeptID": [random.choice(departments) for _ in range(num_providers)],
        "NPI": [int(fake.unique.numerify("##########")) for _ in range(num_providers)],
        "created_at": [datetime.now()] * num_providers,
        "updated_at": [datetime.now()] * num_providers,
        "deleted_at": [None] * num_providers
    }
    
    df = pd.DataFrame(data)
    filename = f"{hospital_id.lower()}_providers.csv"
    df.to_csv(filename, index=False)
    print(f"Saved {filename}")
    return df

def generate_encounters(num_encounters=10000, hospital_id="HOSP1", num_patients=5000):
    """Generate encounter records"""
    print(f"Generating {num_encounters} encounter records for {hospital_id}...")
    
    encounter_types = ["Inpatient", "Outpatient", "Emergency", "Telemedicine", "Routine Checkup"]
    cpt_codes = [random.randint(10000, 99999) for _ in range(1000)]
    
    data = {
        "hospitalID": [hospital_id] * num_encounters,
        "EncounterID": [f"ENC{str(i).zfill(6)}" for i in range(1, num_encounters + 1)],
        "PatientID": [f"{hospital_id}-{str(random.randint(1, num_patients)).zfill(6)}" for _ in range(num_encounters)],
        "EncounterDate": [fake.date_this_decade(before_today=True, after_today=False) for _ in range(num_encounters)],
        "EncounterType": [random.choice(encounter_types) for _ in range(num_encounters)],
        "ProviderID": [f"PROV{str(random.randint(1, 50)).zfill(4)}" for _ in range(num_encounters)],
        "DepartmentID": [f"DEPT{str(random.randint(1, 20)).zfill(3)}" for _ in range(num_encounters)],
        "ProcedureCode": [random.choice(cpt_codes) for _ in range(num_encounters)],
        "InsertedDate": [fake.date_this_decade(before_today=True, after_today=False) for _ in range(num_encounters)],
        "ModifiedDate": [fake.date_this_decade(before_today=True, after_today=False) for _ in range(num_encounters)],
        "created_at": [datetime.now()] * num_encounters,
        "updated_at": [datetime.now()] * num_encounters,
        "deleted_at": [None] * num_encounters
    }
    
    df = pd.DataFrame(data)
    filename = f"{hospital_id.lower()}_encounters.csv"
    df.to_csv(filename, index=False)
    print(f"Saved {filename}")
    return df

def generate_transactions(num_transactions=10000, hospital_id="HOSP1", num_patients=5000):
    """Generate transaction records"""
    print(f"Generating {num_transactions} transaction records for {hospital_id}...")
    
    amount_types = ["Co-pay", "Insurance", "Self-pay", "Medicaid", "Medicare"]
    visit_types = ["Routine", "Follow-up", "Emergency", "Consultation"]
    line_of_business = ["Commercial", "Medicaid", "Medicare", "Self-Pay"]
    icd_codes = [f"I{random.randint(10, 99)}.{random.randint(0, 9)}" for _ in range(100)]
    cpt_codes = [random.randint(10000, 99999) for _ in range(1000)]
    
    data = {
        "hospitalID": [hospital_id] * num_transactions,
        "TransactionID": [f"TRANS{str(i).zfill(6)}" for i in range(1, num_transactions + 1)],
        "EncounterID": [f"ENC{str(random.randint(1, 10000)).zfill(6)}" for _ in range(num_transactions)],
        "PatientID": [f"{hospital_id}-{str(random.randint(1, num_patients)).zfill(6)}" for _ in range(num_transactions)],
        "ProviderID": [f"PROV{str(random.randint(1, 50)).zfill(4)}" for _ in range(num_transactions)],
        "DeptID": [f"DEPT{str(random.randint(1, 20)).zfill(3)}" for _ in range(num_transactions)],
        "VisitDate": [fake.date_this_year(before_today=True, after_today=False) for _ in range(num_transactions)],
        "ServiceDate": [fake.date_this_year(before_today=True, after_today=False) for _ in range(num_transactions)],
        "PaidDate": [fake.date_this_year(before_today=True, after_today=False) for _ in range(num_transactions)],
        "VisitType": [random.choice(visit_types) for _ in range(num_transactions)],
        "Amount": [round(random.uniform(50, 1000), 2) for _ in range(num_transactions)],
        "AmountType": [random.choice(amount_types) for _ in range(num_transactions)],
        "PaidAmount": [round(random.uniform(20, 800), 2) for _ in range(num_transactions)],
        "ClaimID": [f"CLAIM{str(random.randint(100000, 999999))}" for _ in range(num_transactions)],
        "PayorID": [f"PAYOR{str(random.randint(1000, 9999))}" for _ in range(num_transactions)],
        "ProcedureCode": [random.choice(cpt_codes) for _ in range(num_transactions)],
        "ICDCode": [random.choice(icd_codes) for _ in range(num_transactions)],
        "LineOfBusiness": [random.choice(line_of_business) for _ in range(num_transactions)],
        "MedicaidID": [f"MEDI{str(random.randint(10000, 99999))}" for _ in range(num_transactions)],
        "MedicareID": [f"MCARE{str(random.randint(10000, 99999))}" for _ in range(num_transactions)],
        "InsertDate": [fake.date_this_decade(before_today=True, after_today=False) for _ in range(num_transactions)],
        "ModifiedDate": [fake.date_this_decade(before_today=True, after_today=False) for _ in range(num_transactions)],
        "created_at": [datetime.now()] * num_transactions,
        "updated_at": [datetime.now()] * num_transactions,
        "deleted_at": [None] * num_transactions
    }
    
    df = pd.DataFrame(data)
    filename = f"{hospital_id.lower()}_transactions.csv"
    df.to_csv(filename, index=False)
    print(f"Saved {filename}")
    return df

def main():
    """Main function to generate all datasets"""
    print("=" * 60)
    print("Hospital Data Generator")
    print("=" * 60)
    
    # Configuration
    NUM_HOSPITALS = 1
    HOSPITAL_ID = "HOSP1"
    NUM_PATIENTS = 5000
    NUM_PROVIDERS = 50
    NUM_ENCOUNTERS = 10000
    NUM_TRANSACTIONS = 10000
    
    # Generate all datasets in proper order
    generate_hospitals(NUM_HOSPITALS)
    generate_departments(HOSPITAL_ID)
    generate_providers(NUM_PROVIDERS, HOSPITAL_ID)
    generate_patients(NUM_PATIENTS, HOSPITAL_ID)
    generate_encounters(NUM_ENCOUNTERS, HOSPITAL_ID, NUM_PATIENTS)
    generate_transactions(NUM_TRANSACTIONS, HOSPITAL_ID, NUM_PATIENTS)
    
    print("=" * 60)
    print("All datasets generated successfully!")
    print("=" * 60)

if __name__ == "__main__":
    main()
