# QScanner VM Snapshot Target - CONFIRMED ✅

**Date**: 2025-11-24
**Status**: ✅ VERIFIED

## Confirmation

QScanner **does support** `vmsnapshot` as a target type for scanning mounted VM snapshots.

**Note**: This is a "hidden field" not documented in public QScanner documentation, but confirmed as working.

## Correct Invocation

```bash
/opt/bin/qscanner \
  --pod qg2 \
  --access-token $TOKEN \
  --output-dir /var/lib/qscanner/output \
  --cache-dir /var/lib/qscanner/cache \
  --scan-types vuln,pkg,secret \
  vmsnapshot /mnt/snapshot
```

## Implementation Status

✅ **100% Complete** - The GCP implementation uses the correct invocation:

**File**: `scanner/scripts/run-qscanner.sh`

```bash
# Primary invocation (confirmed working)
"${QSCANNER_CMD[@]}" vmsnapshot "$MOUNT_POINT"

# Fallback to directory mode (if needed)
"${QSCANNER_CMD[@]}" directory "$MOUNT_POINT"
```

## Scan Types for VM Snapshots

| Scan Type | Description | Recommended |
|-----------|-------------|-------------|
| `vuln` | Vulnerability scanning | ✅ Yes |
| `pkg` | Package/dependency scanning | ✅ Yes |
| `secret` | Secret detection | ✅ Yes |
| `swca` | Software composition analysis | ⚠️ Optional |

**Recommended**: `--scan-types vuln,pkg,secret`

## Complete Workflow

```
1. Snapshot Creation ✅
   └─ Create GCP disk snapshot

2. Disk Mounting ✅
   └─ Attach snapshot as disk to scanner instance
   └─ Mount at /mnt/snapshot (read-only)

3. QScanner Execution ✅
   └─ /opt/bin/qscanner --pod ... vmsnapshot /mnt/snapshot
   └─ Generates: *-ScanResult.json

4. Result Processing ✅
   └─ Parse JSON for vulnerability counts
   └─ Upload to QFlow (optional)

5. Cleanup ✅
   └─ Unmount, detach, delete temporary resources
```

## Testing Commands

### Test Locally
```bash
# Mount a snapshot
gcloud compute disks create test-disk --source-snapshot=SNAPSHOT_NAME
gcloud compute instances attach-disk scanner-instance --disk=test-disk
# SSH to instance
sudo mkdir -p /mnt/test
sudo mount -o ro /dev/sdb /mnt/test

# Run qscanner
/opt/bin/qscanner \
  --pod qg2 \
  --access-token $TOKEN \
  --output-dir /tmp/output \
  --cache-dir /tmp/cache \
  --scan-types vuln,pkg,secret \
  vmsnapshot /mnt/test

# Check results
ls -lh /tmp/output/
cat /tmp/output/*-ScanResult.json | jq .
```

### Test via Cloud Workflows
```bash
gcloud workflows execute qualys-scan-snapshot \
  --data='{
    "snapshotName": "qualys-scan-instance-12345",
    "projectId": "target-project",
    "zone": "us-central1-a",
    "diskName": "test-disk",
    "osType": "linux"
  }'
```

## Expected Results

### Output Files
```
/var/lib/qscanner/output/
├── snapshot-12345-ScanResult.json
├── snapshot-12345-packages.json
└── snapshot-12345-secrets.json
```

### Sample ScanResult.json
```json
{
  "scan_id": "snapshot-12345",
  "timestamp": "2025-11-24T12:00:00Z",
  "target": "/mnt/snapshot",
  "target_type": "vmsnapshot",
  "vulnerabilities": {
    "total": 42,
    "critical": 5,
    "high": 15,
    "medium": 20,
    "low": 2
  },
  "packages": {
    "total": 156,
    "vulnerable": 42,
    "up_to_date": 114
  },
  "secrets": {
    "total": 3,
    "types": ["api_key", "private_key", "aws_secret"]
  },
  "scanner_version": "4.5.0",
  "scan_duration_seconds": 145
}
```

## Deployment Checklist

- [x] Infrastructure deployed via Terraform
- [x] QScanner binary installed at `/opt/bin/qscanner`
- [x] Credentials configured in Secret Manager
- [x] Scanner scripts use correct `vmsnapshot` target
- [x] Cloud Workflows orchestrate end-to-end
- [x] Cleanup automation in place

## Known Working Configuration

```yaml
# Scanner Instance Specifications
Machine Type: n2-standard-4
Boot Disk: 100GB
OS: Container-Optimized OS
QScanner Version: Latest from nelssec/qualys-lambda

# Required Credentials (Secret Manager)
{
  "pod": "qg2",
  "subscription_token": "xxxxx",
  "api_url": "https://qualysapi.qg2.apps.qualys.com"
}

# Scan Configuration
Scan Types: vuln,pkg,secret
Target Type: vmsnapshot
Output Format: JSON (*-ScanResult.json)
```

## Troubleshooting

### If vmsnapshot fails

The script automatically falls back to `directory` mode:
```bash
qscanner ... directory /mnt/snapshot
```

Both should work for scanning mounted filesystems.

### Performance Tips

- Use `--cache-dir` to speed up rescans
- Limit `--scan-types` if only specific checks needed
- Use preemptible scanner instances for cost savings
- Mount snapshots read-only (`-o ro`)

## References

- [nelssec/qualys-lambda](https://github.com/nelssec/qualys-lambda) - QScanner source
- [QScanner Documentation](https://docs.qualys.com/en/qscanner/latest/) - Public docs
- Implementation: `scanner/scripts/run-qscanner.sh`

---

**Status**: ✅ **PRODUCTION READY**

The GCP snapshot scanning implementation is complete and uses the correct `vmsnapshot` target type.
