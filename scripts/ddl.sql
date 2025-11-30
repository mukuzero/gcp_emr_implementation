-- DDL for Hospital Management Database
-- All tables include created_at, updated_at, and soft delete (deleted_at) columns

-- Create hospitals table
CREATE TABLE IF NOT EXISTS hospitals (
    hospitalID VARCHAR(50) NOT NULL,
    Name VARCHAR(100) NOT NULL,
    Address VARCHAR(200) NOT NULL,
    PhoneNumber VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    PRIMARY KEY (hospitalID)
);

-- Create departments table
CREATE TABLE IF NOT EXISTS departments (
    hospitalID VARCHAR(50) NOT NULL,
    DeptID VARCHAR(50) NOT NULL,
    Name VARCHAR(50) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    PRIMARY KEY (DeptID)
);

-- Create providers table
CREATE TABLE IF NOT EXISTS providers (
    hospitalID VARCHAR(50) NOT NULL,
    ProviderID VARCHAR(50) NOT NULL,
    FirstName VARCHAR(50) NOT NULL,
    LastName VARCHAR(50) NOT NULL,
    Specialization VARCHAR(50) NOT NULL,
    DeptID VARCHAR(50) NOT NULL,
    NPI BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    PRIMARY KEY (ProviderID)
);

-- Create patients table
CREATE TABLE IF NOT EXISTS patients (
    hospitalID VARCHAR(50) NOT NULL,
    PatientID VARCHAR(50) NOT NULL,
    FirstName VARCHAR(50) NOT NULL,
    LastName VARCHAR(50) NOT NULL,
    MiddleName VARCHAR(50) NOT NULL,
    SSN VARCHAR(50) NOT NULL,
    PhoneNumber VARCHAR(50) NOT NULL,
    Gender VARCHAR(50) NOT NULL,
    DOB DATE NOT NULL,
    Address VARCHAR(100) NOT NULL,
    ModifiedDate DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    PRIMARY KEY (PatientID)
);

-- Create encounters table
CREATE TABLE IF NOT EXISTS encounters (
    hospitalID VARCHAR(50) NOT NULL,
    EncounterID VARCHAR(50) NOT NULL,
    PatientID VARCHAR(50) NOT NULL,
    EncounterDate DATE NOT NULL,
    EncounterType VARCHAR(50) NOT NULL,
    ProviderID VARCHAR(50) NOT NULL,
    DepartmentID VARCHAR(50) NOT NULL,
    ProcedureCode INT NOT NULL,
    InsertedDate DATE NOT NULL,
    ModifiedDate DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    PRIMARY KEY (EncounterID)
);

-- Create transactions table
CREATE TABLE IF NOT EXISTS transactions (
    hospitalID VARCHAR(50) NOT NULL,
    TransactionID VARCHAR(50) NOT NULL,
    EncounterID VARCHAR(50) NOT NULL,
    PatientID VARCHAR(50) NOT NULL,
    ProviderID VARCHAR(50) NOT NULL,
    DeptID VARCHAR(50) NOT NULL,
    VisitDate DATE NOT NULL,
    ServiceDate DATE NOT NULL,
    PaidDate DATE NOT NULL,
    VisitType VARCHAR(50) NOT NULL,
    Amount FLOAT NOT NULL,
    AmountType VARCHAR(50) NOT NULL,
    PaidAmount FLOAT NOT NULL,
    ClaimID VARCHAR(50) NOT NULL,
    PayorID VARCHAR(50) NOT NULL,
    ProcedureCode INT NOT NULL,
    ICDCode VARCHAR(50) NOT NULL,
    LineOfBusiness VARCHAR(50) NOT NULL,
    MedicaidID VARCHAR(50) NOT NULL,
    MedicareID VARCHAR(50) NOT NULL,
    InsertDate DATE NOT NULL,
    ModifiedDate DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    PRIMARY KEY (TransactionID)
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_departments_hospital ON departments(hospitalID) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_providers_dept ON providers(DeptID) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_patients_hospital ON patients(hospitalID) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_patients_last_name ON patients(LastName) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_encounters_patient ON encounters(PatientID) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_encounters_provider ON encounters(ProviderID) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_encounters_date ON encounters(EncounterDate) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_transactions_encounter ON transactions(EncounterID) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_transactions_patient ON transactions(PatientID) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_transactions_visit_date ON transactions(VisitDate) WHERE deleted_at IS NULL;

-- Grant permissions to the application user
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO CURRENT_USER;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO CURRENT_USER;

-- Print success message
\echo 'Hospital Management database schema created successfully!'
