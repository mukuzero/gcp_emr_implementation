# GCP Low-Tier Database Infrastructure with Terraform & GitHub Actions

This repository contains Terraform code to provision a cost-effective PostgreSQL database on Google Cloud Platform (GCP). It includes a CI/CD pipeline using GitHub Actions to automatically validate and plan infrastructure changes when a Pull Request is opened.

---

## 1. Code Walkthrough & Explanation

Here is a detailed breakdown of the files and code in this repository.

### `terraform/provider.tf`
This file tells Terraform which cloud provider to talk to.

```hcl
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0" # Use the Google provider version 5.x
    }
  }
  required_version = ">= 1.0" # Requires Terraform CLI version 1.0 or newer
}

provider "google" {
  project = var.project_id # The GCP Project ID (passed as a variable)
  region  = var.region     # The GCP Region (e.g., us-central1)
}
```

### `terraform/variables.tf`
Defines the inputs required to build the infrastructure. This makes the code reusable.

*   `project_id`: Your specific GCP project ID.
*   `region`: Defaults to `us-central1` (Iowa), which is generally cheaper and reliable.
*   `db_password`: Marked as `sensitive = true` so Terraform hides it in logs.

### `terraform/main.tf`
This is where the actual resources are defined.

**1. Database Instance (`google_sql_database_instance`)**
```hcl
resource "google_sql_database_instance" "default" {
  name             = "low-tier-db-instance-${random_id.db_name_suffix.hex}"
  database_version = "POSTGRES_15" # Using a modern Postgres version
  region           = var.region

  settings {
    # COST SAVING CONFIGURATIONS:
    tier = "db-f1-micro"        # The smallest shared-core machine type available.
    availability_type = "ZONAL" # "ZONAL" means no automatic failover to another zone (cheaper than REGIONAL).
    disk_type = "PD_HDD"        # Standard magnetic drive (HDD) is cheaper than SSD.
    disk_size = 10              # 10 GB is the minimum allowed size.

    ip_configuration {
      ipv4_enabled = true       # Assigns a public IP so you can connect from outside (e.g., your laptop).
    }
  }
  deletion_protection = false   # IMPORTANT: Allows you to destroy the DB easily with Terraform. Set to true for production.
}
```

**2. Random ID (`random_id`)**
*   Generates a random suffix for the database instance name. Cloud SQL instance names must be unique globally (or within the project depending on context), so this prevents naming conflicts.

**3. Database (`google_sql_database`)**
*   Creates the actual logical database named `my-database` inside the instance.

**4. User (`google_sql_user`)**
*   Creates a user `db-user` with the password provided via the variable.

---

## 2. CI/CD Workflow (`.github/workflows/terraform.yml`)

This YAML file defines the automation process.

*   **Trigger (`on: pull_request`)**: This workflow runs *only* when you open a Pull Request targeting the `master` branch.
*   **Job (`terraform`)**:
    1.  **Checkout**: Downloads your code.
    2.  **Setup Terraform**: Installs the Terraform CLI.
    3.  **Terraform Init**: Initializes the working directory (downloads the Google provider).
    4.  **Terraform Plan**: Compares your code against the real GCP environment and calculates what changes need to be made.
        *   It injects secrets (`GOOGLE_CREDENTIALS`, `DB_PASSWORD`) securely from GitHub Secrets.

---

## 3. Setup Guide

### Prerequisites
1.  **Google Cloud Project**: Create a project in the GCP Console.
2.  **Billing**: Enable billing for the project.
3.  **APIs**: Enable the **Cloud SQL Admin API** and **Compute Engine API**.

### Step 1: Create a Service Account
1.  Go to **IAM & Admin** > **Service Accounts** in GCP.
2.  Create a new Service Account (e.g., `terraform-sa`).
3.  Grant it the following roles:
    *   **Cloud SQL Admin**
    *   **Storage Admin** (for state files, if you configure remote state later)
    *   **Viewer** (basic read access)
4.  Click on the Service Account > **Keys** > **Add Key** > **Create new key** > **JSON**.
5.  Download the JSON file. **Keep this safe!**

### Step 2: Configure GitHub Secrets
1.  Go to your GitHub Repository.
2.  Navigate to **Settings** > **Secrets and variables** > **Actions**.
3.  Add the following Repository Secrets:
    *   `GOOGLE_CREDENTIALS`: Paste the *entire content* of the JSON key file you downloaded.
    *   `GCP_PROJECT_ID`: Your GCP Project ID (e.g., `my-project-123`).
    *   `DB_PASSWORD`: A strong password for your database user.

---

## 4. The Workflow & Process

### Branching Strategy
*   **`master`**: This is the "Production" branch. The code here should always represent what is currently deployed (or ready to be deployed).
*   **`feature/your-feature-name`**: Create these branches for every new task (e.g., `feature/add-read-replica`, `feature/change-disk-size`).

### Step-by-Step Development Process

**1. Start a new task**
Open your terminal and create a new branch:
```bash
git checkout -b feature/upgrade-db-version
```

**2. Make Changes**
Edit the `terraform/main.tf` file. For example, change `disk_size` from `10` to `20`.

**3. Test Locally (Optional but Recommended)**
If you have Terraform installed locally and authenticated:
```bash
cd terraform
terraform init
terraform validate  # Checks for syntax errors
terraform plan      # Shows what will happen
```

**4. Push and Open a PR**
```bash
git add .
git commit -m "Increase disk size to 20GB"
git push origin feature/upgrade-db-version
```
*   Go to GitHub and click **"Compare & pull request"**.
*   Set the **base** branch to `master` and **compare** branch to `feature/upgrade-db-version`.

**5. Automated "Testing" (The CI Pipeline)**
*   Once the PR is created, the **Terraform Plan** GitHub Action will automatically start.
*   Wait for the check to turn Green.
*   Click "Details" on the action to see the `terraform plan` output. It will show you exactly what resources will be created, modified, or destroyed.

**6. Review and Approval**
*   **Who approves?** In a team setting, a generic "DevOps Engineer" or "Tech Lead" would review the `plan` output to ensure no destructive changes (like deleting the DB) are happening accidentally.
*   If this is a personal project, you are the approver. Review the plan yourself to ensure it matches your expectations.

**7. Merge**
*   If the plan looks good, click **"Merge pull request"**.

### How to Deploy (Apply)
Currently, the automation only *plans* the changes. To apply them:

**Option A: Manual Apply (Simplest for now)**
After merging to master, pull the changes locally and run:
```bash
git checkout master
git pull
cd terraform
terraform apply
```

**Option B: Automate Apply (Advanced)**
You can create a second GitHub Action workflow that triggers on `push` to `master` and runs `terraform apply -auto-approve`.
