#!/bin/bash
set -e

# Log everything
exec > >(tee /var/log/validation-startup.log)
exec 2>&1

echo "=== Validation Startup Script Started ==="
echo "Timestamp: $(date)"

# Get instance name from metadata
INSTANCE_NAME=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name)

# Download validation scripts from GCS bucket
echo "Downloading validation scripts from GCS bucket..."
mkdir -p /tmp/validation
gsutil -m cp -r gs://validation-scripts-sandbox-dev-478813/validation/* /tmp/validation/ || {
  echo "ERROR: Failed to download validation scripts from GCS"
  exit 1
}

# Copy to home directory
cp -r /tmp/validation ~/validation
cd ~/validation

# Make scripts executable
chmod +x *.sh

echo "Running master validation script (validate_all.sh)..."
echo "=========================================="

# Run validation script
bash validate_all.sh
VALIDATION_EXIT_CODE=$?

echo "=========================================="
echo "Validation exit code: ${VALIDATION_EXIT_CODE}"

# Write result to metadata (so workflow can read it)
if [ ${VALIDATION_EXIT_CODE} -eq 0 ]; then
  VALIDATION_RESULT="Pass"
  echo "VALIDATION: PASS"
else
  VALIDATION_RESULT="Fail"
  echo "VALIDATION: FAIL (exit code: ${VALIDATION_EXIT_CODE})"
fi

# Write result to metadata (try first)
# Get project ID from metadata
PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)

gcloud compute instances add-metadata ${INSTANCE_NAME} \
  --zone=us-central1-a \
  --project=${PROJECT_ID} \
  --metadata=validation_result="${VALIDATION_RESULT}" \
  --metadata=validation_exit_code="${VALIDATION_EXIT_CODE}" || {
  echo "Warning: Could not write to metadata"
}

# PRIMARY METHOD: Write result to GCS bucket file (most reliable)
# This file can be read directly by the workflow without SSH
VALIDATION_BUCKET="validation-scripts-sandbox-dev-478813"
RESULT_FILE="gs://${VALIDATION_BUCKET}/validation-results/${INSTANCE_NAME}-result.json"

# Create JSON result file
cat > /tmp/validation_result.json << EOF
{
  "instance_name": "${INSTANCE_NAME}",
  "validation_result": "${VALIDATION_RESULT}",
  "validation_exit_code": ${VALIDATION_EXIT_CODE},
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# Upload to GCS bucket
echo "Uploading validation result to GCS: ${RESULT_FILE}"
gsutil cp /tmp/validation_result.json "${RESULT_FILE}" || {
  echo "ERROR: Failed to upload validation result to GCS"
  # Still continue - metadata or log fallback may work
}

echo "=== Validation Startup Script Completed ==="
echo "Result: ${VALIDATION_RESULT}"
echo "Result file: ${RESULT_FILE}"

