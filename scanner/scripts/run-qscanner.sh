#!/bin/bash
# Run Qualys QScanner on mounted VM snapshot
# Based on nelssec/qualys-lambda implementation

set -euo pipefail

# Arguments
MOUNT_POINT="${1:?Mount point required}"
SNAPSHOT_NAME="${2:?Snapshot name required}"
OUTPUT_DIR="${3:-/var/lib/qscanner/output}"
CACHE_DIR="${4:-/var/lib/qscanner/cache}"

# Configuration
QSCANNER_BIN="${QSCANNER_BIN:-/opt/bin/qscanner}"
LOG_FILE="/var/log/qualys-scanner.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

# Check if qscanner binary exists
if [ ! -f "$QSCANNER_BIN" ]; then
    error "QScanner binary not found at: $QSCANNER_BIN"
    error "Please download qscanner from: https://github.com/nelssec/qualys-lambda/blob/main/scanner-lambda/qscanner.gz"
    exit 1
fi

# Get Qualys credentials
log "Fetching Qualys credentials..."
QUALYS_CREDS=$(gcloud secrets versions access latest \
    --secret="${QUALYS_SECRET_NAME}" \
    --project="${GCP_PROJECT_ID}")

POD=$(echo "$QUALYS_CREDS" | jq -r '.pod // "qg2"')
ACCESS_TOKEN=$(echo "$QUALYS_CREDS" | jq -r '.subscription_token')
QUALYS_USERNAME=$(echo "$QUALYS_CREDS" | jq -r '.username // empty')
QUALYS_PASSWORD=$(echo "$QUALYS_CREDS" | jq -r '.password // empty')

# Create output directories
mkdir -p "$OUTPUT_DIR" "$CACHE_DIR"

log "=== Starting QScanner ==="
log "Mount Point: $MOUNT_POINT"
log "Snapshot: $SNAPSHOT_NAME"
log "Output Dir: $OUTPUT_DIR"
log "Pod: $POD"

# Construct qscanner command
# Based on: https://github.com/nelssec/qualys-lambda/blob/main/scanner-lambda/lambda_function.py
QSCANNER_CMD=(
    "$QSCANNER_BIN"
    "--pod" "$POD"
    "--access-token" "$ACCESS_TOKEN"
    "--output-dir" "$OUTPUT_DIR"
    "--cache-dir" "$CACHE_DIR"
)

# Add scan types
# For VM snapshots: vulnerabilities, packages, and secrets
SCAN_TYPES="vuln,pkg,secret"
QSCANNER_CMD+=("--scan-types" "$SCAN_TYPES")

# Add registry credentials if available (for scanning images within the VM)
if [ -n "$QUALYS_USERNAME" ] && [ -n "$QUALYS_PASSWORD" ]; then
    export REGISTRY_USERNAME="$QUALYS_USERNAME"
    export REGISTRY_PASSWORD="$QUALYS_PASSWORD"
fi

# Specify scan target
# For VM snapshots, we need to determine the correct target type
# Options might be: vmsnapshot, filesystem, or directory scan
# This needs validation from Qualys documentation

# Attempt 1: VM snapshot mode (if supported)
log "Attempting VM snapshot scan mode..."
if "${QSCANNER_CMD[@]}" vmsnapshot "$MOUNT_POINT" 2>&1 | tee -a "$LOG_FILE"; then
    SCAN_SUCCESS=true
    log "VM snapshot scan completed successfully"
else
    SCAN_EXIT=$?
    log "VM snapshot mode failed with exit code: $SCAN_EXIT"
    SCAN_SUCCESS=false

    # Attempt 2: Directory scan mode (fallback)
    log "Attempting directory scan mode..."
    if "${QSCANNER_CMD[@]}" directory "$MOUNT_POINT" 2>&1 | tee -a "$LOG_FILE"; then
        SCAN_SUCCESS=true
        log "Directory scan completed successfully"
    else
        SCAN_EXIT=$?
        error "Directory scan also failed with exit code: $SCAN_EXIT"
        SCAN_SUCCESS=false
    fi
fi

if [ "$SCAN_SUCCESS" = true ]; then
    log "=== Scan Complete ==="

    # List generated results
    log "Scan results:"
    ls -lh "$OUTPUT_DIR"

    # Look for ScanResult.json files (pattern from Lambda implementation)
    RESULT_FILES=$(find "$OUTPUT_DIR" -name "*-ScanResult.json" 2>/dev/null || true)

    if [ -n "$RESULT_FILES" ]; then
        log "Found scan result files:"
        echo "$RESULT_FILES" | tee -a "$LOG_FILE"

        # Parse and display summary
        for result_file in $RESULT_FILES; do
            log "Processing: $result_file"

            # Extract vulnerability counts (if JSON structure similar to Lambda)
            if command -v jq >/dev/null 2>&1; then
                VULN_COUNT=$(jq -r '.vulnerabilities.count // 0' "$result_file" 2>/dev/null || echo "0")
                SECRET_COUNT=$(jq -r '.secrets.count // 0' "$result_file" 2>/dev/null || echo "0")

                log "  Vulnerabilities: $VULN_COUNT"
                log "  Secrets: $SECRET_COUNT"
            fi
        done

        exit 0
    else
        log "WARNING: No ScanResult.json files found in $OUTPUT_DIR"
        log "Scan may have completed but results in unexpected format"
        exit 0
    fi
else
    error "=== Scan Failed ==="
    error "QScanner exited with errors"
    error "Check logs above for details"
    exit 1
fi
