# QScanner Setup

## Overview

QScanner is the Qualys binary that performs vulnerability scanning on mounted VM snapshots.

## Download

```bash
wget https://github.com/nelssec/qualys-lambda/raw/main/scanner-lambda/qscanner.gz
gunzip qscanner.gz
chmod +x qscanner
```

## Installation

### Option 1: Manual Installation (Post-Deployment)

After deploying infrastructure, install on each scanner instance:

```bash
# List scanner instances
gcloud compute instances list \
  --filter="labels.app=qualys-snapshot-scanner" \
  --project=YOUR_SERVICE_PROJECT

# Copy to each instance
gcloud compute scp qscanner INSTANCE_NAME:/tmp/ \
  --zone=ZONE --project=YOUR_SERVICE_PROJECT

# Install
gcloud compute ssh INSTANCE_NAME --zone=ZONE --project=YOUR_SERVICE_PROJECT \
  --command="sudo mkdir -p /opt/bin && \
             sudo mv /tmp/qscanner /opt/bin/qscanner && \
             sudo chmod +x /opt/bin/qscanner"
```

### Option 2: Automated Installation (Pre-Deployment)

Add to `terraform/modules/scanner/cloud-init.yaml` before deploying:

```yaml
runcmd:
  - wget https://github.com/nelssec/qualys-lambda/raw/main/scanner-lambda/qscanner.gz -O /tmp/qscanner.gz
  - gunzip /tmp/qscanner.gz
  - chmod +x /tmp/qscanner
  - mkdir -p /opt/bin
  - mv /tmp/qscanner /opt/bin/qscanner
  - /opt/bin/qscanner --version
```

### Option 3: Custom Scanner Image

Create a scanner image with qscanner pre-installed:

```bash
# Create base instance
gcloud compute instances create qscanner-base \
  --image-family=cos-stable --image-project=cos-cloud \
  --zone=us-central1-a

# Install qscanner
gcloud compute scp qscanner qscanner-base:/tmp/
gcloud compute ssh qscanner-base --command="\
  sudo mkdir -p /opt/bin && \
  sudo mv /tmp/qscanner /opt/bin/qscanner && \
  sudo chmod +x /opt/bin/qscanner"

# Create image
gcloud compute images create qualys-scanner-image \
  --source-disk=qscanner-base \
  --source-disk-zone=us-central1-a

# Update terraform/modules/scanner/main.tf to use custom image
# disk {
#   source_image = "projects/YOUR_PROJECT/global/images/qualys-scanner-image"
# }
```

## Invocation

QScanner is automatically invoked by scanner scripts when a scan is triggered:

```bash
/opt/bin/qscanner \
  --pod qg2 \
  --access-token $TOKEN \
  --output-dir /var/lib/qscanner/output \
  --cache-dir /var/lib/qscanner/cache \
  --scan-types vuln,pkg,secret \
  vmsnapshot /mnt/snapshot
```

**Parameters:**
- `--pod`: Qualys POD (qg2, qg3, qg4, etc.)
- `--access-token`: Subscription token from Secret Manager
- `--output-dir`: Where to write scan results
- `--cache-dir`: Cache directory for performance
- `--scan-types`: Types of scans (vuln,pkg,secret)
- `vmsnapshot`: Target type for VM snapshot scanning
- `/mnt/snapshot`: Path to mounted snapshot

**Scan Types:**
- `vuln`: Vulnerability scanning
- `pkg`: Package/dependency analysis
- `secret`: Secret detection

## Verification

Check qscanner is installed correctly:

```bash
gcloud compute ssh SCANNER_INSTANCE --zone=ZONE \
  --command="/opt/bin/qscanner --version"
```

Test scan on mounted filesystem:

```bash
# SSH to scanner instance
gcloud compute ssh SCANNER_INSTANCE --zone=ZONE

# Create test directory
sudo mkdir -p /tmp/test-scan
echo "test" | sudo tee /tmp/test-scan/test.txt

# Run qscanner (requires Qualys credentials)
sudo /opt/bin/qscanner \
  --pod qg2 \
  --access-token $TOKEN \
  --output-dir /tmp/output \
  --scan-types vuln,pkg,secret \
  vmsnapshot /tmp/test-scan

# Check output
ls -la /tmp/output/
```

## Output Format

QScanner generates JSON files:

```
/var/lib/qscanner/output/
└── *-ScanResult.json
```

**Example structure:**
```json
{
  "vulnerabilities": {
    "total": 42,
    "critical": 5,
    "high": 15,
    "medium": 20,
    "low": 2
  },
  "packages": {
    "total": 156,
    "vulnerable": 42
  },
  "secrets": {
    "total": 3
  }
}
```

## Troubleshooting

**QScanner not found:**
```bash
# Verify installation
gcloud compute ssh SCANNER_INSTANCE --command="ls -l /opt/bin/qscanner"

# Check permissions
gcloud compute ssh SCANNER_INSTANCE --command="sudo chmod +x /opt/bin/qscanner"
```

**Authentication errors:**
```bash
# Verify credentials
gcloud secrets versions access latest --secret=qualys-credentials | jq .

# Test API connectivity
gcloud compute ssh SCANNER_INSTANCE \
  --command="curl -v https://qualysapi.qg2.apps.qualys.com"
```

**Scan failures:**
```bash
# Check scanner logs
gcloud compute ssh SCANNER_INSTANCE \
  --command="sudo journalctl -u google-startup-scripts -n 100"

# Verify disk mounted
gcloud compute ssh SCANNER_INSTANCE \
  --command="mount | grep /mnt"
```

## Performance Tuning

**Cache Directory:**
- QScanner uses cache for faster subsequent scans
- Mount persistent disk at `/var/lib/qscanner/cache`
- Reduces scan time by 30-50% for rescans

**Scan Types:**
- Use only required scan types
- `vuln` is fastest, `pkg` adds overhead
- `secret` scanning is resource-intensive

**Timeouts:**
- Default: 3600 seconds (1 hour)
- Adjust in `terraform.tfvars`: `scan_timeout_seconds`
- Large disks may require longer timeouts
