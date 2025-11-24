#!/bin/bash
# Main scan orchestration script
# Called by Cloud Workflows to scan a snapshot

set -euo pipefail

# Arguments
SNAPSHOT_NAME="${1:?Snapshot name required}"
DISK_NAME="${2:?Disk name required}"
OS_TYPE="${3:-linux}"

# Configuration
SCANNER_HOME="/opt/qualys-scanner"
SCRIPTS_DIR="$SCANNER_HOME/scripts"
MOUNT_POINT="/mnt/snapshots/$DISK_NAME"
OUTPUT_DIR="/var/lib/qscanner"
LOG_FILE="/var/log/qualys-scanner.log"

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

# Ensure bootstrap has run
if [ ! -d "$SCRIPTS_DIR" ] || [ ! -f "$SCRIPTS_DIR/scan-linux.sh" ]; then
    log "Scanner not bootstrapped, running bootstrap"
    bash /opt/qualys-scanner/bootstrap-scanner.sh
fi

# Main scan process
main() {
    log "=== Starting Scan ==="
    log "Snapshot: $SNAPSHOT_NAME"
    log "Disk: $DISK_NAME"
    log "OS Type: $OS_TYPE"

    # Create mount point
    mkdir -p "$MOUNT_POINT"

    # Wait for disk to be attached
    DEVICE="/dev/disk/by-id/google-$DISK_NAME"
    log "Waiting for disk device: $DEVICE"

    if ! timeout 120 bash -c "until [ -e $DEVICE ]; do sleep 2; done"; then
        error "Timeout waiting for disk $DEVICE"
        exit 1
    fi

    log "Disk attached: $DEVICE"

    # Mount the disk
    log "Mounting disk..."
    if [ "$OS_TYPE" = "windows" ]; then
        # Windows NTFS - may need ntfs-3g
        if mount -t ntfs-3g -o ro "$DEVICE" "$MOUNT_POINT" 2>&1 | tee -a "$LOG_FILE"; then
            log "Mounted Windows filesystem"
        else
            error "Failed to mount Windows filesystem"
            exit 1
        fi
    else
        # Linux - try ext4 first, then xfs
        if mount -o ro "$DEVICE" "$MOUNT_POINT" 2>&1 | tee -a "$LOG_FILE"; then
            log "Mounted Linux filesystem"
        elif mount -t xfs -o ro,nouuid "$DEVICE" "$MOUNT_POINT" 2>&1 | tee -a "$LOG_FILE"; then
            log "Mounted XFS filesystem"
        else
            error "Failed to mount Linux filesystem"
            exit 1
        fi
    fi

    # Verify mount
    if ! mountpoint -q "$MOUNT_POINT"; then
        error "Mount point $MOUNT_POINT is not mounted"
        exit 1
    fi

    log "Mount successful. Contents:"
    ls -la "$MOUNT_POINT" | head -20 | tee -a "$LOG_FILE"

    # Run appropriate scanner script
    log "Executing scanner..."
    if [ "$OS_TYPE" = "windows" ]; then
        bash "$SCRIPTS_DIR/scan-windows.sh" "$MOUNT_POINT" "$SNAPSHOT_NAME" "$OUTPUT_DIR"
    else
        bash "$SCRIPTS_DIR/scan-linux.sh" "$MOUNT_POINT" "$SNAPSHOT_NAME" "$OUTPUT_DIR"
    fi

    SCAN_EXIT_CODE=$?

    # Unmount
    log "Unmounting disk..."
    if umount "$MOUNT_POINT"; then
        log "Unmounted successfully"
    else
        error "Failed to unmount (may retry)"
        umount -l "$MOUNT_POINT" || true
    fi

    # Check scan results
    if [ $SCAN_EXIT_CODE -ne 0 ]; then
        error "Scanner exited with code $SCAN_EXIT_CODE"
        exit $SCAN_EXIT_CODE
    fi

    # Upload results to QFlow
    log "Uploading results to QFlow..."
    if [ -f "$SCRIPTS_DIR/upload-results.sh" ]; then
        bash "$SCRIPTS_DIR/upload-results.sh" "$OUTPUT_DIR" "$SNAPSHOT_NAME"
    else
        log "WARNING: upload-results.sh not found, attempting manual upload"
        upload_results_manual
    fi

    log "=== Scan Complete ==="
}

# Manual upload fallback
upload_results_manual() {
    # Get credentials
    QUALYS_CREDS=$(gcloud secrets versions access latest \
        --secret="${QUALYS_SECRET_NAME}" \
        --project="${GCP_PROJECT_ID}")

    QUALYS_TOKEN=$(echo "$QUALYS_CREDS" | jq -r '.subscription_token')
    QUALYS_API_URL=$(echo "$QUALYS_CREDS" | jq -r '.api_url')

    # Look for results files
    for result_file in "$OUTPUT_DIR"/*.{db,json,xml}; do
        if [ -f "$result_file" ]; then
            log "Uploading $result_file..."

            # Try QFlow snapshot upload endpoint (similar to AWS)
            if curl -f -X POST \
                -H "Authorization: Bearer $QUALYS_TOKEN" \
                -F "file=@$result_file" \
                -F "snapshot_name=$SNAPSHOT_NAME" \
                -F "cloud_provider=gcp" \
                "$QUALYS_API_URL/qflow/snapshot/v1/upload" 2>&1 | tee -a "$LOG_FILE"; then
                log "Upload successful: $result_file"
            else
                error "Upload failed for $result_file"
            fi
        fi
    done
}

# Execute
main "$@"
