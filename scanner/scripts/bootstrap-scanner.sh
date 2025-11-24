#!/bin/bash
# Bootstrap script for Qualys GCP Scanner Instance
# Downloads scanner scripts from QFlow API and executes scans

set -euo pipefail

# Configuration from environment/metadata
PROJECT_ID="${GCP_PROJECT_ID:-}"
QUALYS_SECRET_NAME="${QUALYS_SECRET_NAME:-qualys-credentials}"
QFLOW_API_BASE="${QFLOW_API_BASE:-https://qualysapi.qualys.com}"
SCANNER_VERSION="${SCANNER_VERSION:-latest}"

# Directories
SCANNER_HOME="/opt/qualys-scanner"
SCRIPTS_DIR="$SCANNER_HOME/scripts"
OUTPUT_DIR="/var/lib/qscanner"
LOG_FILE="/var/log/qualys-scanner.log"

# Logging
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

# Get Qualys credentials from Secret Manager
get_qualys_credentials() {
    log "Fetching Qualys credentials from Secret Manager"

    if ! QUALYS_CREDS=$(gcloud secrets versions access latest \
        --secret="$QUALYS_SECRET_NAME" \
        --project="$PROJECT_ID" 2>&1); then
        error "Failed to fetch credentials: $QUALYS_CREDS"
        return 1
    fi

    export QUALYS_USERNAME=$(echo "$QUALYS_CREDS" | jq -r '.username')
    export QUALYS_PASSWORD=$(echo "$QUALYS_CREDS" | jq -r '.password')
    export QUALYS_API_URL=$(echo "$QUALYS_CREDS" | jq -r '.api_url')
    export QUALYS_TOKEN=$(echo "$QUALYS_CREDS" | jq -r '.subscription_token')

    log "Credentials fetched successfully"
}

# Download scanner scripts from QFlow API
download_scanner_scripts() {
    log "Downloading scanner scripts from QFlow API"

    mkdir -p "$SCRIPTS_DIR"

    # Get version mapping first (similar to AWS implementation)
    local version_url="$QFLOW_API_BASE/qflow/v1/version/mapping/qscanner-gcp-orchestrator"
    version_url+="?version=$SCANNER_VERSION&module=GCP_SCANNER&release=GA"

    log "Fetching version mapping from: $version_url"

    if ! VERSION_INFO=$(curl -s -f \
        -H "Authorization: Bearer $QUALYS_TOKEN" \
        "$version_url" 2>&1); then
        error "Failed to fetch version mapping: $VERSION_INFO"
        error "This may indicate that GCP snapshot scanning is not yet supported"
        error "Falling back to local scanner implementation"
        return 1
    fi

    log "Version mapping: $VERSION_INFO"

    # Download scanner scripts (similar to /qflow/aws-snapshot/v1/scripts/**)
    local scripts_url="$QFLOW_API_BASE/qflow/gcp-snapshot/v1/scripts"

    # List of expected scripts
    local scripts=(
        "scan-linux.sh"
        "scan-windows.sh"
        "mount-snapshot.sh"
        "upload-results.sh"
    )

    for script in "${scripts[@]}"; do
        log "Downloading $script..."

        if curl -s -f \
            -H "Authorization: Bearer $QUALYS_TOKEN" \
            -o "$SCRIPTS_DIR/$script" \
            "$scripts_url/$script"; then
            chmod +x "$SCRIPTS_DIR/$script"
            log "Downloaded and made executable: $script"
        else
            error "Failed to download $script (may not exist yet for GCP)"
        fi
    done

    return 0
}

# Fallback: Use built-in scanner logic if QFlow scripts not available
use_builtin_scanner() {
    log "Using built-in scanner logic (QFlow GCP scripts not available yet)"

    cat > "$SCRIPTS_DIR/scan-linux.sh" << 'EOFSCRIPT'
#!/bin/bash
# Built-in Linux scanner (placeholder until Qualys provides GCP scripts)
set -euo pipefail

MOUNT_POINT="$1"
SNAPSHOT_NAME="$2"
OUTPUT_DIR="${3:-/var/lib/qscanner}"

echo "[SCAN] Scanning Linux filesystem at $MOUNT_POINT"
echo "[SCAN] Snapshot: $SNAPSHOT_NAME"

# Detect OS
if [ -f "$MOUNT_POINT/etc/os-release" ]; then
    . "$MOUNT_POINT/etc/os-release"
    echo "[SCAN] Detected OS: $NAME $VERSION"
fi

# Check for qscanner binary or container
if command -v qscanner >/dev/null 2>&1; then
    echo "[SCAN] Using qscanner binary"
    # TODO: Determine correct qscanner command for VM snapshot scanning
    # This may require Qualys-specific build or parameters
    qscanner --help || true

elif command -v docker >/dev/null 2>&1; then
    echo "[SCAN] Using qscanner Docker container"

    # Try to run qscanner container (if it supports VM scanning)
    docker run --rm --privileged \
        -v "$MOUNT_POINT:/mnt/scan:ro" \
        -v "$OUTPUT_DIR:/output" \
        qualys/qscanner:latest \
        --help || true

    # Log what we attempted
    echo "[SCAN] NOTE: qscanner container invocation may need adjustment"
    echo "[SCAN] Contact Qualys for correct VM snapshot scanning parameters"
fi

# Generate placeholder output
mkdir -p "$OUTPUT_DIR"
cat > "$OUTPUT_DIR/scan-results.json" << EOF
{
  "snapshot": "$SNAPSHOT_NAME",
  "timestamp": "$(date -Iseconds)",
  "status": "placeholder",
  "note": "This is a placeholder. Actual scanning requires Qualys-provided scanner."
}
EOF

echo "[SCAN] Placeholder results generated at $OUTPUT_DIR/scan-results.json"
EOFSCRIPT

    chmod +x "$SCRIPTS_DIR/scan-linux.sh"

    # Similar for Windows
    cat > "$SCRIPTS_DIR/scan-windows.sh" << 'EOFSCRIPT'
#!/bin/bash
# Built-in Windows scanner (placeholder until Qualys provides GCP scripts)
set -euo pipefail

MOUNT_POINT="$1"
SNAPSHOT_NAME="$2"
OUTPUT_DIR="${3:-/var/lib/qscanner}"

echo "[SCAN] Scanning Windows filesystem at $MOUNT_POINT"
echo "[SCAN] Snapshot: $SNAPSHOT_NAME"

# Detect Windows version
if [ -f "$MOUNT_POINT/Windows/System32/config/SOFTWARE" ]; then
    echo "[SCAN] Detected Windows installation"
fi

# Generate placeholder output
mkdir -p "$OUTPUT_DIR"
cat > "$OUTPUT_DIR/scan-results.json" << EOF
{
  "snapshot": "$SNAPSHOT_NAME",
  "timestamp": "$(date -Iseconds)",
  "status": "placeholder",
  "note": "This is a placeholder. Actual scanning requires Qualys-provided scanner."
}
EOF

echo "[SCAN] Placeholder results generated"
EOFSCRIPT

    chmod +x "$SCRIPTS_DIR/scan-windows.sh"
}

# Main execution function
main() {
    log "=== Qualys GCP Scanner Bootstrap ==="
    log "Project ID: $PROJECT_ID"
    log "QFlow API: $QFLOW_API_BASE"

    # Create directories
    mkdir -p "$SCANNER_HOME" "$SCRIPTS_DIR" "$OUTPUT_DIR"

    # Get credentials
    if ! get_qualys_credentials; then
        error "Failed to get credentials. Exiting."
        exit 1
    fi

    # Try to download scripts from QFlow
    if ! download_scanner_scripts; then
        log "QFlow scripts not available, using built-in fallback"
        use_builtin_scanner
    fi

    log "=== Scanner Bootstrap Complete ==="
    log "Scanner scripts available in: $SCRIPTS_DIR"
    log "Ready to process scan requests"

    # List available scripts
    log "Available scanner scripts:"
    ls -lah "$SCRIPTS_DIR/"
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
