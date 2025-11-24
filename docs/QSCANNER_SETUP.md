# QScanner Setup for GCP Snapshot Scanning

## Overview

Based on the [nelssec/qualys-lambda](https://github.com/nelssec/qualys-lambda) implementation, we now know how to properly invoke qscanner for scanning.

## QScanner Binary

### Source

The qscanner binary is available at:
- **Repository**: https://github.com/nelssec/qualys-lambda
- **File**: `scanner-lambda/qscanner.gz` (40MB compressed)
- **Extracted**: `/opt/bin/qscanner`

### Download and Install

```bash
# Download qscanner
wget https://github.com/nelssec/qualys-lambda/raw/main/scanner-lambda/qscanner.gz

# Extract
gunzip qscanner.gz

# Make executable
chmod +x qscanner

# Place in standard location
sudo mkdir -p /opt/bin
sudo mv qscanner /opt/bin/qscanner

# Verify
/opt/bin/qscanner --help
```

## Command-Line Invocation

### Pattern from Lambda Implementation

```bash
qscanner \
  --pod [POD] \
  --access-token [TOKEN] \
  --output-dir /tmp/qscanner-output \
  --cache-dir /tmp/qscanner-cache \
  --scan-types pkg,secret \
  lambda [FUNCTION_ARN]
```

### For VM Snapshot Scanning

```bash
qscanner \
  --pod [POD] \
  --access-token [ACCESS_TOKEN] \
  --output-dir /var/lib/qscanner/output \
  --cache-dir /var/lib/qscanner/cache \
  --scan-types vuln,pkg,secret \
  vmsnapshot /mnt/snapshot
```

**Key Parameters:**

| Parameter | Description | Example |
|-----------|-------------|---------|
| `--pod` | Qualys POD identifier | `qg2`, `qg3`, `qg4` |
| `--access-token` | Qualys subscription token | From Secret Manager |
| `--output-dir` | Where to write results | `/var/lib/qscanner/output` |
| `--cache-dir` | Cache directory | `/var/lib/qscanner/cache` |
| `--scan-types` | Types of scans to run | `vuln,pkg,secret` |
| Target | What to scan | `vmsnapshot /mnt/snapshot` |

### Scan Types

- **`vuln`**: Vulnerability scanning
- **`pkg`**: Package/dependency scanning
- **`secret`**: Secret detection
- **`swca`**: Software composition analysis (may be alias for `pkg`)

### Target Types

Need to determine from Qualys documentation which is correct for VM snapshots:

- **`vmsnapshot [path]`**: VM snapshot scanning (likely)
- **`directory [path]`**: Directory scanning (fallback)
- **`filesystem [path]`**: Filesystem scanning (alternative)

## Output Format

### Result Files

QScanner generates JSON files with pattern: `*-ScanResult.json`

**Example Structure** (based on Lambda implementation):
```json
{
  "vulnerabilities": {
    "count": 42,
    "critical": 5,
    "high": 15,
    "medium": 20,
    "low": 2
  },
  "secrets": {
    "count": 3,
    "types": ["api_key", "private_key", "password"]
  },
  "packages": {
    "count": 156,
    "vulnerable": 42
  },
  "metadata": {
    "scan_time": "2025-11-24T12:00:00Z",
    "scanner_version": "4.5.0",
    "target": "/mnt/snapshot"
  }
}
```

## Integration with GCP Implementation

### 1. Add QScanner Binary to Scanner Instances

**Option A: Startup Script**
```yaml
# In terraform/modules/scanner/cloud-init.yaml
runcmd:
  - curl -L https://github.com/nelssec/qualys-lambda/raw/main/scanner-lambda/qscanner.gz -o /tmp/qscanner.gz
  - gunzip /tmp/qscanner.gz
  - chmod +x /tmp/qscanner
  - mkdir -p /opt/bin
  - mv /tmp/qscanner /opt/bin/qscanner
```

**Option B: Custom Image**
```bash
# Build scanner image with qscanner pre-installed
gcloud compute images create qualys-scanner-v1 \
  --source-disk=source-disk \
  --source-disk-zone=us-central1-a
```

**Option C: Container Image**
```dockerfile
# Dockerfile for scanner container
FROM gcr.io/google.com/cloudsdktool/google-cloud-cli:alpine

RUN apk add --no-cache bash jq curl

# Download and install qscanner
RUN wget https://github.com/nelssec/qualys-lambda/raw/main/scanner-lambda/qscanner.gz && \
    gunzip qscanner.gz && \
    chmod +x qscanner && \
    mv qscanner /opt/bin/qscanner

COPY scanner/scripts/*.sh /usr/local/bin/

ENTRYPOINT ["/usr/local/bin/scan-snapshot.sh"]
```

### 2. Update Scanner Scripts

The `scanner/scripts/run-qscanner.sh` now has the correct invocation pattern.

### 3. Configure Credentials

Ensure Secret Manager contains:
```json
{
  "pod": "qg2",
  "subscription_token": "your-token-here",
  "username": "optional-username",
  "password": "optional-password",
  "api_url": "https://qualysapi.qg2.apps.qualys.com"
}
```

## Testing QScanner Locally

### 1. Download Test Filesystem

```bash
# Create a test directory structure
mkdir -p /tmp/test-scan/{bin,etc,var/log}
echo "test" > /tmp/test-scan/etc/test.conf

# Add a package manifest
cat > /tmp/test-scan/var/lib/dpkg/status << EOF
Package: nginx
Version: 1.18.0-1
Status: install ok installed
EOF
```

### 2. Run QScanner

```bash
export POD="qg2"
export ACCESS_TOKEN="your-token"

/opt/bin/qscanner \
  --pod "$POD" \
  --access-token "$ACCESS_TOKEN" \
  --output-dir /tmp/qscanner-output \
  --cache-dir /tmp/qscanner-cache \
  --scan-types vuln,pkg,secret \
  directory /tmp/test-scan
```

### 3. Check Results

```bash
# List output files
ls -lh /tmp/qscanner-output/

# View results
cat /tmp/qscanner-output/*-ScanResult.json | jq .
```

## Troubleshooting

### QScanner Not Found

```bash
# Verify installation
ls -l /opt/bin/qscanner
file /opt/bin/qscanner

# Check if executable
/opt/bin/qscanner --version
```

### Authentication Errors

```bash
# Verify credentials
gcloud secrets versions access latest --secret=qualys-credentials | jq .

# Test POD connectivity
curl -v https://qualysapi.qg2.apps.qualys.com
```

### No Results Generated

```bash
# Check output directory permissions
ls -ld /var/lib/qscanner/output

# Run with verbose logging
/opt/bin/qscanner --log-level debug ...

# Check qscanner logs
journalctl -u qscanner
```

### Scan Target Type Error

```bash
# Try different target types
qscanner ... vmsnapshot /mnt/scan    # Primary
qscanner ... directory /mnt/scan     # Fallback
qscanner ... filesystem /mnt/scan    # Alternative
```

## Next Steps

1. **Verify Target Type**: Confirm with Qualys whether `vmsnapshot`, `directory`, or another type is correct
2. **Test End-to-End**: Deploy infrastructure and run a complete scan
3. **Validate Results**: Ensure scan results upload correctly to QFlow
4. **Optimize Performance**: Tune scan types and caching for your workload

## References

- [nelssec/qualys-lambda](https://github.com/nelssec/qualys-lambda) - Reference implementation
- [QScanner Documentation](https://docs.qualys.com/en/qscanner/latest/) - Official docs
- [Qualys PODs](https://www.qualys.com/platform-identification/) - POD identifiers

---

**Status**: ✅ QScanner invocation pattern confirmed from Lambda implementation
