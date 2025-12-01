#!/bin/bash
# Don't use set -e - we need to ensure result is always written to GCS

# Log everything
exec > >(tee /var/log/validation-startup.log)
exec 2>&1

echo "=== Validation Startup Script Started ==="
echo "Timestamp: $(date)"

# Get instance name from metadata
INSTANCE_NAME=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name)
echo "Instance name: ${INSTANCE_NAME}"

# Initialize validation result variables
VALIDATION_EXIT_CODE=1
VALIDATION_RESULT="Fail"

# Download validation scripts from GCS bucket
echo "Downloading validation scripts from GCS bucket..."
mkdir -p /tmp/validation
if gsutil -m cp -r gs://validation-scripts-sandbox-dev-478813/validation/* /tmp/validation/ 2>&1; then
  echo "Successfully downloaded validation scripts"
else
  echo "ERROR: Failed to download validation scripts from GCS"
  # Write failure result to GCS before exiting
  VALIDATION_BUCKET="validation-scripts-sandbox-dev-478813"
  RESULT_FILE="gs://${VALIDATION_BUCKET}/validation-results/${INSTANCE_NAME}-result.json"
  cat > /tmp/validation_result.json << EOF
{
  "instance_name": "${INSTANCE_NAME}",
  "validation_result": "Fail",
  "validation_exit_code": 1,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "error": "Failed to download validation scripts from GCS"
}
EOF
  gsutil cp /tmp/validation_result.json "${RESULT_FILE}" 2>&1 || echo "ERROR: Could not write result to GCS"
  exit 1
fi

# Copy to home directory
cp -r /tmp/validation ~/validation
cd ~/validation

# Make scripts executable
chmod +x *.sh

echo "Running master validation script (validate_all.sh)..."
echo "=========================================="
echo "Current directory: $(pwd)"
echo "Scripts available:"
ls -la *.sh || echo "No .sh files found"

# Run validation script - capture exit code even if it fails
echo "Executing: bash validate_all.sh"
if bash validate_all.sh 2>&1; then
  VALIDATION_EXIT_CODE=0
  echo "VALIDATION SCRIPT COMPLETED WITH EXIT CODE: 0"
else
  VALIDATION_EXIT_CODE=$?
  echo "VALIDATION SCRIPT COMPLETED WITH EXIT CODE: ${VALIDATION_EXIT_CODE}"
fi

echo "=========================================="
echo "Validation exit code: ${VALIDATION_EXIT_CODE}"

# Determine validation result
if [ ${VALIDATION_EXIT_CODE} -eq 0 ]; then
  VALIDATION_RESULT="Pass"
  echo "VALIDATION: PASS"
else
  VALIDATION_RESULT="Fail"
  echo "VALIDATION: FAIL (exit code: ${VALIDATION_EXIT_CODE})"
fi

# PRIMARY METHOD: Write result to GCS bucket file (MUST ALWAYS HAPPEN)
# This file can be read directly by the workflow without SSH
VALIDATION_BUCKET="validation-scripts-sandbox-dev-478813"
RESULT_FILE="gs://${VALIDATION_BUCKET}/validation-results/${INSTANCE_NAME}-result.json"

echo "Preparing to write result to GCS..."
echo "Result file path: ${RESULT_FILE}"

# Create JSON result file
cat > /tmp/validation_result.json << EOF
{
  "instance_name": "${INSTANCE_NAME}",
  "validation_result": "${VALIDATION_RESULT}",
  "validation_exit_code": ${VALIDATION_EXIT_CODE},
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

echo "Result JSON file created:"
cat /tmp/validation_result.json

# Upload to GCS bucket - CRITICAL: This must succeed
echo "Uploading validation result to GCS: ${RESULT_FILE}"
echo "Attempt 1: Uploading to GCS..."
if gsutil cp /tmp/validation_result.json "${RESULT_FILE}" 2>&1; then
  echo "SUCCESS: Validation result uploaded to GCS: ${RESULT_FILE}"
  echo "Verifying upload..."
  if gsutil ls "${RESULT_FILE}" 2>&1; then
    echo "CONFIRMED: File exists in GCS bucket"
  else
    echo "WARNING: File upload reported success but file not found in GCS"
  fi
else
  UPLOAD_ERROR=$?
  echo "ERROR: Failed to upload validation result to GCS (exit code: ${UPLOAD_ERROR})"
  echo "Retrying in 5 seconds..."
  sleep 5
  echo "Attempt 2: Retrying upload to GCS..."
  if gsutil cp /tmp/validation_result.json "${RESULT_FILE}" 2>&1; then
    echo "SUCCESS: Validation result uploaded to GCS on retry: ${RESULT_FILE}"
  else
    RETRY_ERROR=$?
    echo "CRITICAL ERROR: Could not write validation result to GCS after retry (exit code: ${RETRY_ERROR})"
    echo "Checking gsutil availability..."
    which gsutil || echo "gsutil not found in PATH"
    echo "Checking service account..."
    gcloud auth list 2>&1 || echo "gcloud auth failed"
    # Try writing to metadata as fallback
    PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
    echo "Attempting to write to metadata as fallback..."
    gcloud compute instances add-metadata ${INSTANCE_NAME} \
      --zone=us-central1-a \
      --project=${PROJECT_ID} \
      --metadata=validation_result="${VALIDATION_RESULT}" \
      --metadata=validation_exit_code="${VALIDATION_EXIT_CODE}" 2>&1 || echo "Could not write to metadata either"
  fi
fi

echo "=== Validation Startup Script Completed ==="
echo "Result: ${VALIDATION_RESULT}"
echo "Result file: ${RESULT_FILE}"
echo "Exit code: ${VALIDATION_EXIT_CODE}"

