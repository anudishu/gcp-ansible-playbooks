# Image Validation and Promotion Workflow

A Cloud Workflows-based automation pipeline that validates RHEL images and promotes them to a display project upon successful validation.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Configuration](#configuration)
- [Workflow Steps](#workflow-steps)
- [Usage](#usage)
- [Output](#output)
- [Troubleshooting](#troubleshooting)
- [File Structure](#file-structure)

---

## 🎯 Overview

This workflow automates the process of:
1. **Creating a validation VM** from a candidate image
2. **Running validation scripts** to verify all required packages/roles are installed
3. **Promoting the image** to a display project if validation passes
4. **Cleaning up** temporary resources

### Key Features

- ✅ **Sequential/Synchronous Execution** - Each step waits for completion
- ✅ **GCS-Based Result Storage** - Validation results stored in GCS bucket
- ✅ **SSH-Based Validation** - Uses OS Login for secure VM access
- ✅ **Automatic Image Promotion** - Promotes validated images with labels
- ✅ **Resource Cleanup** - Automatically removes validation VMs

---

## 🏗️ Architecture

### Visual Workflow Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    WORKFLOW EXECUTION START                      │
└────────────────────────────┬────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │   INIT STEP      │
                    │  - Set defaults  │
                    │  - Load params   │
                    └────────┬──────────┘
                             │
                             ▼
        ┌────────────────────────────────────────┐
        │     VALIDATION STEP                     │
        │  ┌──────────────────────────────────┐  │
        │  │ 1. Create VM with OS Login        │  │
        │  │    (External IP enabled)          │  │
        │  └────────────┬───────────────────────┘  │
        │               │                           │
        │               ▼                           │
        │  ┌──────────────────────────────────┐  │
        │  │ 2. Wait 60s for VM to boot         │  │
        │  └────────────┬───────────────────────┘  │
        │               │                           │
        │               ▼                           │
        │  ┌──────────────────────────────────┐  │
        │  │ 3. SSH to VM (OS Login)           │  │
        │  │    Download validation scripts    │  │
        │  │    from GCS bucket                │  │
        │  └────────────┬───────────────────────┘  │
        │               │                           │
        │               ▼                           │
        │  ┌──────────────────────────────────┐  │
        │  │ 4. Run validate_all.sh            │  │
        │  │    Check Python, Java, Node.js,   │  │
        │  │    PostgreSQL, etc.               │  │
        │  └────────────┬───────────────────────┘  │
        │               │                           │
        │               ▼                           │
        │  ┌──────────────────────────────────┐  │
        │  │ 5. Write result to GCS bucket     │  │
        │  │    gs://bucket/validation-results/ │  │
        │  └────────────┬───────────────────────┘  │
        └───────────────┼───────────────────────────┘
                        │
                        ▼
              ┌─────────────────┐
              │  CHECK RESULT   │
              │  scan_result?   │
              └────────┬────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
        ▼              ▼              ▼
    ┌────────┐   ┌──────────┐   ┌──────────┐
    │  FAIL  │   │   PASS   │   │  SKIP    │
    └───┬────┘   └─────┬────┘   └─────┬────┘
        │              │              │
        │              ▼              │
        │      ┌──────────────┐       │
        │      │  PROMOTION   │       │
        │      │  Copy image  │       │
        │      │  to display  │       │
        │      │  project     │       │
        │      └──────┬───────┘       │
        │             │                │
        └─────────────┼────────────────┘
                      │
                      ▼
            ┌─────────────────┐
            │  CLEANUP STEP   │
            │  Delete VM      │
            └────────┬─────────┘
                     │
                     ▼
            ┌─────────────────┐
            │  RETURN RESULT  │
            │  Final status   │
            └─────────────────┘
```

### Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    Cloud Workflows                               │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  workflow-new.yml                                        │   │
│  │  - Orchestrates entire process                           │   │
│  │  - Calls Cloud Build steps                              │   │
│  │  - Reads validation results from GCS                     │   │
│  └──────────────────────────────────────────────────────────┘   │
└────────────────────────────┬────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │         Cloud Build                      │
        │  ┌─────────────────────────────────────┐ │
        │  │ Step 1: Create Validation VM        │ │
        │  │ Step 2: SSH & Run Validation       │ │
        │  │ Step 3: Write Result to GCS         │ │
        │  │ Step 4: Promote Image (if Pass)     │ │
        │  │ Step 5: Cleanup VM                  │ │
        │  └─────────────────────────────────────┘ │
        └───────────────┬───────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
        ▼               ▼               ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│  Compute     │ │  GCS Bucket  │ │  Display     │
│  Engine      │ │              │ │  Project    │
│              │ │  validation/ │ │              │
│  Validation  │ │  - scripts   │ │  Promoted   │
│  VM          │ │              │ │  Images     │
│              │ │  validation- │ │              │
│  - OS Login  │ │  results/     │ │  spoke-     │
│  - External  │ │  - results    │ │  project1-  │
│    IP        │ │              │ │  476804     │
└──────────────┘ └──────────────┘ └──────────────┘
```

---

## 📦 Prerequisites

### Required GCP Services

- **Cloud Workflows** API enabled
- **Cloud Build** API enabled
- **Compute Engine** API enabled
- **Cloud Storage** API enabled

### Required Permissions

The following service accounts need permissions:

#### In Source Project (`sandbox-dev-478813`):
- `sa-kitchen-sh@sandbox-dev-478813.iam.gserviceaccount.com`
  - `roles/compute.instanceAdmin.v1`
  - `roles/compute.storageAdmin`
  - `roles/storage.admin`
  - `roles/compute.imageUser`

#### In Display Project (`spoke-project1-476804`):
- `21623636966-compute@developer.gserviceaccount.com`
  - `roles/compute.admin`
  - `roles/compute.imageUser`
- `21623636966@cloudbuild.gserviceaccount.com`
  - `roles/compute.admin`
  - `roles/compute.imageUser`

### GCS Bucket Structure

```
gs://validation-scripts-sandbox-dev-478813/
├── validation/
│   ├── validate_all.sh          # Master validation script
│   ├── validate_python.sh        # Python validation
│   ├── validate_java.sh          # Java validation
│   ├── validate_nodejs.sh        # Node.js validation
│   ├── validate_postgresql.sh    # PostgreSQL validation
│   └── ... (other validation scripts)
└── validation-results/
    └── {instance-name}-result.json  # Validation results (auto-created)
```

---

## ⚙️ Configuration

### Workflow Parameters

The workflow accepts the following input parameters:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `image_id` | `test-rhel-vm-image` | Name of the candidate image to validate |
| `display_project_id` | `spoke-project1-476804` | Target project for image promotion |
| `validation_bucket` | `validation-scripts-sandbox-dev-478813` | GCS bucket with validation scripts |

### Default Values

```yaml
project_id: sandbox-dev-478813
image_id: test-rhel-vm-image
display_project_id: spoke-project1-476804
validation_bucket: validation-scripts-sandbox-dev-478813
```

---

## 🔄 Workflow Steps

### Step 1: Initialization

```yaml
- Load input parameters
- Set default values
- Initialize workflow variables
```

**What happens:**
- Reads input parameters or uses defaults
- Sets project IDs and bucket names
- Prepares for validation step

---

### Step 2: Validation

#### 2.1 Create Validation VM

```bash
gcloud compute instances create {image_id}-validation
  --image=projects/sandbox-dev-478813/global/images/{image_id}
  --machine-type=n1-standard-1
  --zone=us-central1-a
  --service-account=sa-kitchen-sh@sandbox-dev-478813.iam.gserviceaccount.com
  --scopes=cloud-platform
  --metadata=enable-oslogin=TRUE
```

**What happens:**
- Creates VM from candidate image
- Enables OS Login for SSH access
- Assigns external IP address
- Attaches service account with required permissions

#### 2.2 Wait for VM Boot

```bash
sleep 60  # Wait for VM to be ready
```

**What happens:**
- Waits 60 seconds for VM to fully boot
- Ensures SSH service is ready

#### 2.3 Download Validation Scripts

```bash
gcloud compute ssh {instance_name}
  --command="mkdir -p ~/validation && \
            gsutil -m cp -r gs://bucket/validation/* ~/validation/ && \
            chmod +x ~/validation/*.sh"
```

**What happens:**
- SSH into VM using OS Login
- Downloads all validation scripts from GCS bucket
- Makes scripts executable

#### 2.4 Run Validation

```bash
gcloud compute ssh {instance_name}
  --command="cd ~/validation && bash validate_all.sh"
```

**What happens:**
- Executes master validation script
- Validates all required packages:
  - ✅ Python
  - ✅ Java
  - ✅ Node.js
  - ✅ PostgreSQL
  - ✅ Other configured packages
- Captures exit code (0 = Pass, non-zero = Fail)

#### 2.5 Write Result to GCS

```bash
# Create result JSON
{
  "instance_name": "{instance_name}",
  "validation_result": "Pass" or "Fail",
  "validation_exit_code": 0 or 1,
  "timestamp": "2025-12-01T17:14:31Z"
}

# Upload to GCS
gsutil cp /tmp/validation_result.json \
  gs://bucket/validation-results/{instance_name}-result.json
```

**What happens:**
- Creates JSON file with validation result
- Uploads to GCS bucket in `validation-results/` folder
- Workflow reads this file to determine next steps

---

### Step 3: Check Result

```yaml
if validation_result == "Pass":
  → Proceed to Promotion
else:
  → Skip Promotion, go to Cleanup
```

**What happens:**
- Reads validation result from GCS bucket
- Decides whether to promote image
- Only promotes if validation passed

---

### Step 4: Promotion (if Pass)

```bash
gcloud compute images create {image_id}
  --source-image=projects/{source_project}/global/images/{image_id}
  --project={display_project}
  --description="Promoted validated image from {source_project}"
  --family="rhel9-runtime"
  --labels=source_image="{image_id}",\
           source_project="{source_project}",\
           validation_status="passed",\
           promoted_date="{YYYYMMDD}"
```

**What happens:**
- Copies image from source project to display project
- Adds descriptive labels
- Waits for image to be READY
- Preserves all source image properties

**Labels Added:**
- `source_image`: Original image name
- `source_project`: Source project ID
- `validation_status`: "passed"
- `promoted_date`: Date of promotion (YYYYMMDD)

---

### Step 5: Cleanup

```bash
# Stop VM
gcloud compute instances stop {instance_name} --zone=us-central1-a

# Delete VM
gcloud compute instances delete {instance_name} --zone=us-central1-a
```

**What happens:**
- Stops validation VM
- Deletes validation VM
- **Note:** Candidate image is preserved (not deleted)

---

## 🚀 Usage

### Basic Execution

```bash
gcloud workflows execute workflow-new \
  --location=us-central1 \
  --project=sandbox-dev-478813
```

### With Custom Parameters

```bash
gcloud workflows execute workflow-new \
  --location=us-central1 \
  --project=sandbox-dev-478813 \
  --data='{
    "image_id": "my-custom-image",
    "display_project_id": "my-display-project"
  }'
```

### Monitor Execution

```bash
# List recent executions
gcloud workflows executions list \
  --workflow=workflow-new \
  --location=us-central1 \
  --project=sandbox-dev-478813

# Check specific execution
gcloud workflows executions describe {execution-id} \
  --workflow=workflow-new \
  --location=us-central1 \
  --project=sandbox-dev-478813
```

---

## 📤 Output

### Successful Execution

```json
{
  "image_id": "test-rhel-vm-image",
  "validation_result": "Pass",
  "validation_instance": "test-rhel-vm-image-validation",
  "promotion_result": "Image promoted successfully",
  "cleanup_result": "VM cleanup completed"
}
```

### Failed Validation

```json
{
  "image_id": "test-rhel-vm-image",
  "validation_result": "Fail",
  "validation_instance": "test-rhel-vm-image-validation",
  "promotion_result": "skipped",
  "cleanup_result": "VM cleanup completed"
}
```

### Validation Result File (GCS)

Location: `gs://validation-scripts-sandbox-dev-478813/validation-results/{instance-name}-result.json`

```json
{
  "instance_name": "test-rhel-vm-image-validation",
  "validation_result": "Pass",
  "validation_exit_code": 0,
  "timestamp": "2025-12-01T17:14:31Z"
}
```

---

## 🔧 Troubleshooting

### Issue: Validation Result Not Found

**Symptoms:**
- Workflow shows "WARNING: Could not read validation result from GCS"
- Defaults to "Fail"

**Solutions:**
1. Check service account permissions:
   ```bash
   gcloud projects get-iam-policy sandbox-dev-478813 \
     --flatten="bindings[].members" \
     --filter="bindings.members:serviceAccount:sa-kitchen-sh@sandbox-dev-478813.iam.gserviceaccount.com"
   ```
2. Verify GCS bucket exists and is accessible
3. Check VM serial console logs:
   ```bash
   gcloud compute instances get-serial-port-output {instance-name} \
     --zone=us-central1-a \
     --project=sandbox-dev-478813
   ```

### Issue: SSH Connection Failed

**Symptoms:**
- "Could not SSH into the instance"

**Solutions:**
1. Ensure VM has external IP (check workflow doesn't use `--no-address`)
2. Verify OS Login is enabled: `--metadata=enable-oslogin=TRUE`
3. Check service account has `roles/compute.osLogin` permission
4. Wait longer for VM to boot (increase sleep time)

### Issue: Image Promotion Failed

**Symptoms:**
- "Required 'compute.images.create' permission"

**Solutions:**
1. Grant permissions to Cloud Build service account:
   ```bash
   gcloud projects add-iam-policy-binding {display-project} \
     --member="serviceAccount:{project-number}@cloudbuild.gserviceaccount.com" \
     --role="roles/compute.admin"
   
   gcloud projects add-iam-policy-binding {display-project} \
     --member="serviceAccount:{project-number}-compute@developer.gserviceaccount.com" \
     --role="roles/compute.admin"
   ```

### Issue: Validation Scripts Not Found

**Symptoms:**
- "ERROR: Failed to download validation scripts from GCS"

**Solutions:**
1. Verify scripts exist in GCS bucket:
   ```bash
   gsutil ls gs://validation-scripts-sandbox-dev-478813/validation/
   ```
2. Check service account has `roles/storage.objectViewer` on bucket
3. Verify bucket name in workflow matches actual bucket

---

## 📁 File Structure

```
shivani-workflow-newcode/
├── workflow-new.yml              # Main workflow definition
├── README.md                     # This file
└── validation/
    ├── startup-validation.sh     # Startup script (legacy, not used)
    ├── validate_all.sh           # Master validation script
    ├── validate_python.sh        # Python validation
    ├── validate_java.sh          # Java validation
    ├── validate_nodejs.sh        # Node.js validation
    ├── validate_postgresql.sh    # PostgreSQL validation
    └── ... (other validation scripts)
```

### Key Files

- **`workflow-new.yml`**: Main Cloud Workflows definition
  - Contains all workflow steps
  - Handles VM creation, validation, promotion, cleanup
  - Reads validation results from GCS

- **`validation/validate_all.sh`**: Master validation script
  - Orchestrates all validation checks
  - Returns exit code 0 if all pass, non-zero if any fail
  - Must be uploaded to GCS bucket

---

## 📊 Workflow Timeline

Typical execution time: **5-8 minutes**

| Step | Duration | Description |
|------|----------|-------------|
| VM Creation | ~30s | Create and boot validation VM |
| SSH & Download | ~30s | SSH to VM, download scripts |
| Validation | ~2-3 min | Run all validation checks |
| Write Result | ~10s | Upload result to GCS |
| Promotion | ~2-3 min | Copy image to display project |
| Cleanup | ~30s | Stop and delete VM |
| **Total** | **5-8 min** | Complete workflow execution |

---

## 🔐 Security Notes

- **OS Login**: Used for secure SSH access without managing SSH keys
- **Service Accounts**: Least privilege principle - only required permissions
- **GCS Bucket**: Validation results stored securely in private bucket
- **No Public Access**: VMs can have external IPs but should be in private subnets

---

## 📝 Notes

- **Candidate Image Preservation**: The original candidate image is never deleted, regardless of validation result
- **Promoted Image**: Only created if validation passes
- **Validation VM**: Always deleted after workflow completes
- **GCS Results**: Validation results are stored permanently in GCS for audit purposes

---

## 🎯 Success Criteria

A successful workflow execution means:

1. ✅ Validation VM created successfully
2. ✅ Validation scripts downloaded from GCS
3. ✅ All validation checks passed (exit code 0)
4. ✅ Result written to GCS bucket
5. ✅ Image promoted to display project (if Pass)
6. ✅ Validation VM cleaned up
7. ✅ Workflow returns success status

---

## 📞 Support

For issues or questions:
1. Check Cloud Build logs for detailed error messages
2. Review VM serial console output
3. Verify all service account permissions
4. Check GCS bucket accessibility

---

**Last Updated:** December 1, 2025  
**Workflow Version:** 1.0  
**Status:** ✅ Production Ready
