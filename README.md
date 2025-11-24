# GCP Low-Tier Database & Dataproc Infrastructure with Terraform & GitHub Actions

This repository contains Terraform code to provision a cost-effective, secure infrastructure on Google Cloud Platform (GCP). It sets up a **Private Cloud SQL (PostgreSQL)** instance and a **Single-Node Dataproc Cluster** within a custom **VPC**, ensuring secure internal communication.

It includes a CI/CD pipeline using GitHub Actions to automatically validate and plan infrastructure changes.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Code Walkthrough & Explanation](#2-code-walkthrough--explanation)
3. [Resource Dependencies](#3-resource-dependencies)
4. [How Dataproc Communicates with Cloud SQL](#4-how-dataproc-communicates-with-cloud-sql)
5. [CI/CD Workflow](#5-cicd-workflow)
6. [Setup Guide](#6-setup-guide)
7. [Deployment & Verification](#7-deployment--verification)
8. [Cost Optimization](#8-cost-optimization)
9. [Security Considerations](#9-security-considerations)

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    YOUR VPC (10.0.0.0/16)                       │
│                                                                 │
│  ┌──────────────────────┐         ┌──────────────────────┐    │
│  │  Dataproc Cluster    │◄───────►│    Cloud SQL DB      │    │
│  │  (e2-standard-2)     │         │  (PostgreSQL 15)     │    │
│  │  IP: 10.0.0.x        │  Port   │  Private IP: 10.x.x.x│    │
│  │  Single Node         │  5432   │  db-f1-micro         │    │
│  └──────────────────────┘         └──────────────────────┘    │
│           │                                  │                  │
│           │                                  │                  │
│  ┌────────▼──────────────────────────────────▼──────────────┐ │
│  │              Subnet (10.0.0.0/16)                        │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │         Firewall: Allow Internal Traffic                 │ │
│  │         Source: 10.0.0.0/16 → Destination: All           │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ VPC Peering Connection
                              ▼
                  ┌───────────────────────────┐
                  │  Google Service Network   │
                  │  (servicenetworking)      │
                  └───────────────────────────┘

🔒 No Public Internet Access - All Traffic is Private
```

---

## 2. Code Walkthrough & Explanation

### `terraform/provider.tf`

This file configures Terraform to use the Google Cloud provider.

```hcl
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0"
}

provider "google" {
  project = var.project_id
  region  = var.region
}
```

**Why:** Tells Terraform which cloud provider (GCP) to use and which version of the provider plugin to download.

---

### `terraform/variables.tf`

Defines all input variables required to customize the infrastructure.

```hcl
variable "project_id" {
  description = "The ID of the GCP project"
  type        = string
}

variable "region" {
  description = "The region to deploy resources in"
  type        = string
  default     = "us-central1"
}

variable "db_password" {
  description = "The password for the database user"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "The name of the database to create"
  type        = string
}

variable "db_user" {
  description = "The name of the database user to create"
  type        = string
}

# ... other variables for VPC, subnet, etc.
```

**Why:** Makes the code reusable and allows different configurations without changing the code. Sensitive values like `db_password` are marked to prevent them from appearing in logs.

---

### `terraform/main.tf`

This is the core file where all infrastructure resources are defined. Let's break down each resource:

#### **Resource 1: VPC Network**

```hcl
resource "google_compute_network" "vpc_network" {
  name                    = var.vpc_network_name
  auto_create_subnetworks = false
}
```

**Purpose:** Creates an isolated virtual network in GCP.

**Why We Need This:**
- Foundation of your network infrastructure
- Isolates your resources from other GCP projects
- `auto_create_subnetworks = false` gives you full control over IP ranges

**Dependencies:** None (created first)

---

#### **Resource 2: Subnet**

```hcl
resource "google_compute_subnetwork" "subnetwork" {
  name          = var.subnetwork_name
  ip_cidr_range = var.subnet_cidr  # 10.0.0.0/16
  region        = var.region
  network       = google_compute_network.vpc_network.id
}
```

**Purpose:** Defines the IP address space for resources in a specific region.

**Why We Need This:**
- Carves out an IP range (10.0.0.0/16 = 65,536 IPs) within your VPC
- Your Dataproc cluster will be deployed here and get an IP from this range
- Regional resource tied to your chosen region

**Dependencies:** Requires VPC Network

---

#### **Resource 3: Private IP Address Range**

```hcl
resource "google_compute_global_address" "private_ip_address" {
  name          = var.private_ip_name
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc_network.id
}
```

**Purpose:** Reserves a block of IP addresses for Google-managed services.

**Why We Need This:**
- Cloud SQL is a managed service that runs in Google's network (not yours)
- This reserves IP space so Cloud SQL can be accessed privately from YOUR VPC
- `purpose = "VPC_PEERING"` specifically for connecting to Google services
- `address_type = "INTERNAL"` means no public internet access

**Dependencies:** Requires VPC Network

---

#### **Resource 4: VPC Peering Connection (CRITICAL!)**

```hcl
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}
```

**Purpose:** Creates a secure tunnel between your VPC and Google's service network.

**Why We Need This (THE MOST IMPORTANT PIECE):**
- This is what enables private communication between Dataproc and Cloud SQL
- Without this, Cloud SQL would need a public IP and you'd connect over the internet
- Creates a VPC peering connection to Google's service producer network
- Uses the reserved IP range from the previous step

**Dependencies:** Requires VPC Network AND Private IP Address Range

---

#### **Resource 5: Cloud SQL Instance**

```hcl
resource "google_sql_database_instance" "default" {
  name             = "${var.db_instance_prefix}-${random_id.db_name_suffix.hex}"
  database_version = "POSTGRES_15"
  region           = var.region

  depends_on = [google_service_networking_connection.private_vpc_connection]

  settings {
    tier              = "db-f1-micro"      # Cheapest option
    availability_type = "ZONAL"            # Single zone (cheaper)
    disk_type         = "PD_HDD"           # HDD instead of SSD
    disk_size         = 10

    ip_configuration {
      ipv4_enabled    = false              # NO PUBLIC IP!
      private_network = google_compute_network.vpc_network.id
    }
  }

  deletion_protection = false  # For dev only!
}
```

**Purpose:** Your PostgreSQL database server.

**Why We Need This:**
- Managed database service - Google handles backups, patches, and scaling
- Your Dataproc Spark jobs will read/write data here
- `ipv4_enabled = false` ensures ONLY private access
- `private_network` links it to your VPC via the peering connection

**Cost Optimizations:**
- `db-f1-micro`: Shared CPU, 0.6GB RAM (cheapest tier)
- `ZONAL`: Single availability zone (cheaper than regional)
- `PD_HDD`: Hard disk drive instead of SSD

**Dependencies:** Requires VPC Peering Connection (explicit `depends_on`)

---

#### **Resource 6: Database and User**

```hcl
resource "google_sql_database" "database" {
  name     = var.db_name
  instance = google_sql_database_instance.default.name
}

resource "google_sql_user" "users" {
  name     = var.db_user
  instance = google_sql_database_instance.default.name
  password = var.db_password
}
```

**Purpose:** Creates the actual database and a user account.

**Why We Need This:**
- The instance is just a server; you need a database inside it
- Creates a user with credentials for your applications to connect

**Dependencies:** Requires Cloud SQL Instance

---

#### **Resource 7: Dataproc Cluster**

```hcl
resource "google_dataproc_cluster" "mycluster" {
  name   = var.dataproc_cluster_name
  region = var.region

  cluster_config {
    master_config {
      num_instances = 1
      machine_type  = "e2-standard-2"  # 2 vCPUs, 8GB RAM
      disk_config {
        boot_disk_type    = "pd-standard"
        boot_disk_size_gb = 30
      }
    }

    worker_config {
      num_instances = 0  # Single-node cluster (no workers)
    }

    software_config {
      image_version = "2.1-debian11"
      override_properties = {
        "dataproc:dataproc.allow.zero.workers" = "true"
      }
    }

    gce_cluster_config {
      subnetwork = google_compute_subnetwork.subnetwork.id
      service_account_scopes = [
        "https://www.googleapis.com/auth/cloud-platform"
      ]
    }
  }
}
```

**Purpose:** Apache Spark/Hadoop cluster for big data processing.

**Why We Need This:**
- Runs your Spark jobs to process large datasets
- Can connect to Cloud SQL via JDBC to read/write data
- Single-node configuration (1 master, 0 workers) for development

**How It Connects to Cloud SQL:**
- Deployed in YOUR subnet (gets IP from 10.0.0.0/16)
- Can reach Cloud SQL's private IP through the VPC peering
- Traffic never leaves Google's private network

**Cost Optimizations:**
- `e2-standard-2`: Cost-effective general-purpose machine
- Zero workers (single node) for development
- Standard persistent disk instead of SSD

**Dependencies:** Requires Subnet

---

#### **Resource 8: Firewall Rule**

```hcl
resource "google_compute_firewall" "allow_internal" {
  name    = var.firewall_rule_name
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_ranges = [var.subnet_cidr]  # 10.0.0.0/16
}
```

**Purpose:** Network security rules that control traffic flow.

**Why We Need This:**
- Allows traffic between resources in your subnet
- Without this, Dataproc couldn't connect to Cloud SQL even though they're in the same VPC
- `source_ranges = 10.0.0.0/16` means only internal traffic is allowed

**⚠️ Security Note:** This rule is too permissive (allows ALL ports). In production, restrict to only port 5432 (PostgreSQL):

```hcl
allow {
  protocol = "tcp"
  ports    = ["5432"]
}
```

**Dependencies:** Requires VPC Network

---

## 3. Resource Dependencies

Understanding the order in which resources must be created:

```
1. VPC Network (google_compute_network)
         │
         ├──► 2. Subnet (google_compute_subnetwork)
         │         │
         │         └──► 6. Dataproc Cluster
         │
         ├──► 3. Private IP Range (google_compute_global_address)
         │         │
         │         └──► 4. VPC Peering (google_service_networking_connection)
         │                     │
         │                     └──► 5. Cloud SQL Instance
         │                               │
         │                               ├──► Database
         │                               └──► User
         │
         └──► 7. Firewall Rule
```

**Key Dependency:** Cloud SQL **MUST** wait for VPC Peering to complete (hence the `depends_on` statement).

---

## 4. How Dataproc Communicates with Cloud SQL

### The Connection Flow (Step by Step)

1. **Your Spark job** in Dataproc creates a JDBC connection to Cloud SQL
   ```python
   jdbc_url = "jdbc:postgresql://10.x.x.x:5432/mydb"
   ```

2. **DNS/IP resolution** occurs - Dataproc looks up Cloud SQL's private IP (10.x.x.x)

3. **Traffic routing** - Packet leaves Dataproc (10.0.0.x) destined for Cloud SQL (10.x.x.x)

4. **VPC peering** routes the packet from your VPC to Google's service network where Cloud SQL lives

5. **Firewall check** - Firewall rule allows traffic from source 10.0.0.0/16

6. **Cloud SQL receives** the connection, authenticates the user (db_user/db_password)

7. **Data flows back and forth** - All traffic stays private within Google's backbone network

### Why This is Secure and Fast

✅ **No Public Internet:** Traffic never leaves Google's private network
✅ **Low Latency:** Direct connection over Google's backbone
✅ **No NAT Gateway Costs:** No need for Cloud NAT or external IPs
✅ **Encrypted:** Google automatically encrypts traffic in transit

---

## 5. CI/CD Workflow

### `.github/workflows/terraform.yml`

This YAML file defines the automation pipeline using GitHub Actions.

```yaml
name: Terraform CI

on:
  pull_request:
    branches: [master]

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v2
      
      - name: Terraform Init
        run: terraform init
      
      - name: Terraform Validate
        run: terraform validate
      
      - name: Terraform Plan
        run: terraform plan
```

**Pipeline Stages:**

1. **Trigger:** Runs automatically on Pull Requests to `master` branch
2. **Setup:** Installs Terraform CLI
3. **Validate:** Checks syntax and configuration
4. **Plan:** Shows what changes would be made (doesn't apply them)

**Benefits:**
- Catches errors before merging
- Shows infrastructure changes in PR comments
- Ensures code quality and consistency

---

## 6. Setup Guide

### Prerequisites

Before you begin, ensure you have:

1. **Google Cloud Project**
   - Create a project in [GCP Console](https://console.cloud.google.com)
   - Note your Project ID

2. **Billing Enabled**
   - Link a billing account to your project

3. **Required APIs Enabled**
   ```bash
   gcloud services enable \
     sqladmin.googleapis.com \
     compute.googleapis.com \
     dataproc.googleapis.com \
     servicenetworking.googleapis.com
   ```

---

### Step 1: Create a Service Account

1. Go to **IAM & Admin** > **Service Accounts** in GCP Console

2. Click **Create Service Account**
   - Name: `terraform-sa`
   - Description: "Service account for Terraform automation"

3. Grant the following roles:
   - ✅ **Cloud SQL Admin**
   - ✅ **Compute Network Admin**
   - ✅ **Dataproc Editor**
   - ✅ **Storage Admin** (for Terraform state)
   - ✅ **Viewer** (for reading project info)

4. Click **Done**, then click on the service account

5. Go to **Keys** tab → **Add Key** → **Create New Key** → **JSON**

6. Download the JSON key file (keep it secure!)

---

### Step 2: Remote Backend Setup

Terraform stores its state in a GCS bucket for team collaboration.

**Option 1: Manual Creation**
```bash
gsutil mb -p YOUR_PROJECT_ID -l us-central1 gs://your-unique-bucket-name
gsutil versioning set on gs://your-unique-bucket-name
```

**Option 2: Automated** (CI/CD pipeline creates it automatically)

Add to `terraform/backend.tf`:
```hcl
terraform {
  backend "gcs" {
    bucket = "your-unique-bucket-name"
    prefix = "terraform/state"
  }
}
```

---

### Step 3: Configure GitHub Secrets

Add the following secrets in your GitHub repository:

Go to **Settings** > **Secrets and variables** > **Actions** > **New repository secret**

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `GOOGLE_CREDENTIALS` | Content of JSON key file | `{"type": "service_account"...}` |
| `GCP_PROJECT_ID` | Your GCP Project ID | `my-project-12345` |
| `GCP_REGION` | Deployment region | `us-central1` |
| `DB_PASSWORD` | PostgreSQL password | `YourSecurePassword123!` |
| `DB_NAME` | Database name | `myapp_db` |
| `DB_USER` | Database username | `dbadmin` |
| `TF_BACKEND_BUCKET` | State bucket name | `my-terraform-state-bucket` |

---

## 7. Deployment & Verification

### Manual Deployment

```bash
# Clone the repository
git clone <your-repo-url>
cd <repo-directory>

# Navigate to terraform directory
cd terraform

# Set your GCP credentials
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account-key.json"

# Initialize Terraform
terraform init

# Review the plan
terraform plan -var="project_id=YOUR_PROJECT_ID" \
               -var="db_password=YOUR_PASSWORD" \
               -var="db_name=mydb" \
               -var="db_user=dbuser"

# Apply the configuration
terraform apply -var="project_id=YOUR_PROJECT_ID" \
                -var="db_password=YOUR_PASSWORD" \
                -var="db_name=mydb" \
                -var="db_user=dbuser"
```

**Expected Output:**
```
Apply complete! Resources: 8 added, 0 changed, 0 destroyed.

Outputs:
db_private_ip = "10.123.45.67"
dataproc_cluster_name = "low-tier-cluster"
```

---

### Verify Connectivity

We've included a script to test that Dataproc can reach Cloud SQL.

#### `scripts/verify_db_access.sh`

This script:
1. Automatically finds the Cloud SQL private IP
2. Submits a PySpark job to Dataproc
3. Tests socket connection to PostgreSQL port (5432)

**Run the verification:**
```bash
# Make script executable
chmod +x scripts/verify_db_access.sh

# Run verification
./scripts/verify_db_access.sh
```

**Expected Success Output:**
```
----------------------------------------------------------------
Finding Cloud SQL Private IP...
Private IP: 10.123.45.67

Submitting PySpark job to Dataproc...
Job submitted: projects/my-project/jobs/verify-db-access-12345

VERIFICATION SUCCESSFUL: Dataproc can reach Cloud SQL on port 5432
----------------------------------------------------------------
```

**If it fails:**
- Check firewall rules
- Verify VPC peering is active: `gcloud services vpc-peerings list --network=dataproc-sql-network`
- Check Cloud SQL instance status: `gcloud sql instances describe <instance-name>`

---

## 8. Cost Optimization

This infrastructure is designed for **minimal cost** suitable for development/testing:

| Resource | Configuration | Monthly Cost (Estimate) |
|----------|---------------|-------------------------|
| Cloud SQL (db-f1-micro) | 0.6GB RAM, HDD, Zonal | ~$7-10 |
| Dataproc (e2-standard-2) | 2 vCPUs, 8GB RAM | ~$50-60* |
| VPC & Networking | Free tier | $0 |
| **Total** | | **~$60-70/month** |

*\*Cost assumes cluster runs 24/7. Use auto-scaling or manual stop/start to reduce costs.*

### Additional Cost-Saving Tips

1. **Stop Dataproc when not in use:**
   ```bash
   gcloud dataproc clusters stop low-tier-cluster --region=us-central1
   ```

2. **Use Dataproc Serverless** for sporadic workloads (pay per job)

3. **Enable Cloud SQL auto-scaling** for production

4. **Use preemptible VMs** for Dataproc workers (not master)

5. **Set up budget alerts** in GCP Console

---

## 9. Security Considerations

### Current Security Features ✅

- ✅ Cloud SQL has **no public IP** (ipv4_enabled = false)
- ✅ All traffic is **internal to VPC**
- ✅ Database password stored as **sensitive variable**
- ✅ Service account with **least privilege roles**

### Recommended Improvements for Production 🔒

1. **Restrict Firewall Rules**
   ```hcl
   allow {
     protocol = "tcp"
     ports    = ["5432"]  # Only PostgreSQL, not all ports
   }
   ```

2. **Use Secret Manager for Passwords**
   ```hcl
   data "google_secret_manager_secret_version" "db_password" {
     secret = "db-password"
   }
   ```

3. **Enable Cloud SQL SSL**
   ```hcl
   ip_configuration {
     require_ssl = true
   }
   ```

4. **Enable deletion protection**
   ```hcl
   deletion_protection = true
   ```

5. **Create dedicated service account for Dataproc**
   ```hcl
   resource "google_service_account" "dataproc_sa" {
     account_id = "dataproc-sa"
   }
   ```

6. **Enable Cloud SQL audit logging**
   ```hcl
   settings {
     database_flags {
       name  = "log_connections"
       value = "on"
     }
   }
   ```

7. **Set up VPC Flow Logs** for network monitoring

---

## Clean Up

To avoid ongoing charges, destroy all resources:

```bash
terraform destroy -var="project_id=YOUR_PROJECT_ID" \
                  -var="db_password=YOUR_PASSWORD" \
                  -var="db_name=mydb" \
                  -var="db_user=dbuser"
```

**Warning:** This will permanently delete all data!

---

## Troubleshooting

### Issue: "Private connection not found"
**Solution:** Ensure VPC peering is established:
```bash
gcloud services vpc-peerings list --network=dataproc-sql-network
```

### Issue: "Connection timed out to Cloud SQL"
**Solution:** Check firewall rules allow traffic from 10.0.0.0/16

### Issue: "API not enabled"
**Solution:** Enable required APIs:
```bash
gcloud services enable servicenetworking.googleapis.com
```

---

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a Pull Request (CI/CD will validate)

---

## License

MIT License - See LICENSE file for details

---

## Support

For issues or questions:
- Open a GitHub Issue
- Check [GCP Documentation](https://cloud.google.com/docs)
- Review [Terraform GCP Provider Docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs)