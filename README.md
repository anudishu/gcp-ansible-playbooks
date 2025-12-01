# Image Validation and Promotion Workflow

A Google Cloud Workflows-based solution for validating VM images and promoting them to production. This workflow uses Cloud Build for VM creation, validation, and image promotion in a fully synchronous model.

## Overview

This workflow automates the process of:
1. **Validating** VM images by running comprehensive runtime checks (Python, Java, Node.js, PostgreSQL)
2. **Promoting** validated images to production
3. **Cleaning up** temporary resources while preserving both candidate and promoted images

## Architecture

```
┌─────────────────┐
│  Input Image    │
│ (test-rhel-...) │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Create VM       │
│ (Cloud Build)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Run Validation  │
│ (startup script) │
│ • Python        │
│ • Java          │
│ • Node.js       │
│ • PostgreSQL    │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
  Pass      Fail
    │         │
    │         └──► Cleanup (VM only)
    │
    ▼
┌─────────────────┐
│ Promote Image   │
│ (Cloud Build)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Cleanup VM     │
│ (Preserve images)│
└─────────────────┘
```

## Prerequisites

- **GCP Project**: `sandbox-dev-478813`
- **APIs Enabled**:
  - Cloud Workflows API
  - Cloud Build API
  - Compute Engine API
- **GCS Bucket**: `validation-scripts-sandbox-dev-478813` with validation scripts
- **Service Account**: `sa-kitchen-sh@sandbox-dev-478813.iam.gserviceaccount.com` with:
  - `roles/compute.instanceAdmin.v1`
  - `roles/storage.objectViewer`
  - `roles/iam.serviceAccountUser`

## Configuration

### Default Values

- **Project ID**: `sandbox-dev-478813`
- **Default Image**: `test-rhel-vm-image`
- **Region**: `us-central1`
- **Zone**: `us-central1-a`
- **Validation Bucket**: `validation-scripts-sandbox-dev-478813`
- **Machine Type**: `n1-standard-1`

### Input Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `image_id` | string | `test-rhel-vm-image` | Source image to validate |
| `instance_name` | string | `""` | Optional validation instance name |
| `override_scan_result` | string | `""` | Force result: `"pass"` or `"fail"` |
| `skip_destroy` | boolean | `false` | Skip VM cleanup |
| `skip_promotion` | boolean | `false` | Skip image promotion |

## Usage

### Deploy Workflow

```bash
gcloud workflows deploy workflow-new \
  --source=workflow-new.yml \
  --location=us-central1 \
  --project=sandbox-dev-478813
```

### Execute Workflow

**Basic execution (uses default image):**
```bash
gcloud workflows execute workflow-new \
  --location=us-central1 \
  --project=sandbox-dev-478813
```

**With custom image:**
```bash
gcloud workflows execute workflow-new \
  --location=us-central1 \
  --project=sandbox-dev-478813 \
  --data='{"image_id":"my-custom-image"}'
```

**With override (skip validation):**
```bash
gcloud workflows execute workflow-new \
  --location=us-central1 \
  --project=sandbox-dev-478813 \
  --data='{"override_scan_result":"pass"}'
```

### Monitor Execution

```bash
# List recent executions
gcloud workflows executions list \
  --workflow=workflow-new \
  --location=us-central1 \
  --project=sandbox-dev-478813

# Get execution details
gcloud workflows executions describe EXECUTION_ID \
  --workflow=workflow-new \
  --location=us-central1 \
  --project=sandbox-dev-478813
```

## Validation Process

The workflow uses a startup script (`startup-validation.sh`) that:

1. Downloads validation scripts from GCS bucket
2. Executes `validate_all.sh` which validates:
   - **Python 3.9+**: Version, pip, standard library, package installation
   - **Java 17**: Runtime, compiler, compilation/execution tests
   - **Node.js 16+**: Version, npm, package installation
   - **PostgreSQL 13+**: Client tools, version
3. Writes result to VM metadata for workflow to read
4. Falls back to log file parsing if metadata unavailable

## Key Features

✅ **Synchronous Execution**: All steps wait for completion  
✅ **Image Preservation**: Both candidate and promoted images are preserved  
✅ **Robust Validation**: Multiple runtime checks with detailed logging  
✅ **Metadata & Log Fallback**: Reads from metadata, falls back to log files  
✅ **Error Handling**: Graceful failure handling with detailed error messages  
✅ **Cloud Build Integration**: Uses Cloud Build for all VM operations  

## Workflow Steps

1. **Validation**: Creates VM, runs validation scripts, determines Pass/Fail
2. **Promotion** (if Pass): Stops VM, creates promoted image with timestamp
3. **Cleanup**: Deletes validation VM, preserves all images

## Output

The workflow returns:
```json
{
  "image_id": "test-rhel-vm-image",
  "scan_result": "Pass",
  "validation_instance": "test-rhel-vm-image-validation",
  "promotion_result": "The image test-rhel-vm-image has been promoted as test-rhel-vm-image-promoted-20251201-120000",
  "cleanup_result": {
    "instance_cleanup": {...},
    "image_cleanup": {...}
  }
}
```

## Troubleshooting

### Validation Fails

- Check VM logs: `/var/log/validation-startup.log`
- Verify validation scripts exist in GCS bucket
- Check service account permissions

### Metadata Not Readable

- Workflow automatically falls back to reading log file via SSH
- Ensure OS Login is enabled on VM
- Verify service account has compute.instanceAdmin permissions

### Image Promotion Fails

- Check if VM is stopped before image creation
- Verify disk exists and is accessible
- Check Cloud Build logs for detailed errors

## File Structure

```
shivani-workflow-newcode/
├── workflow-new.yml          # Main workflow definition
├── validation/
│   ├── startup-validation.sh # VM startup script
│   ├── validate_all.sh       # Master validation script
│   ├── validate_python.sh    # Python validation
│   ├── validate_java.sh      # Java validation
│   ├── validate_node.sh      # Node.js validation
│   └── validate_postgresql.sh # PostgreSQL validation
└── README.md                 # This file
```

## Notes

- **Image Preservation**: Both candidate and promoted images are never deleted by this workflow
- **Validation VM**: Temporary VM is always cleaned up after validation
- **Execution Time**: Typically 5-10 minutes (depends on validation duration)
- **GCS Bucket**: Validation scripts must be uploaded to `gs://validation-scripts-sandbox-dev-478813/validation/`

## Support

For issues or questions:
1. Check Cloud Build logs for detailed error messages
2. Review VM startup logs: `/var/log/validation-startup.log`
3. Check workflow execution logs in GCP Console
