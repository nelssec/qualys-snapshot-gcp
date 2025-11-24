# GCP Snapshot Scanning - Implementation Status

**Last Updated:** 2025-11-24
**Status:** Infrastructure Complete | Scanner Integration Pending

## Summary

This repository provides complete, production-ready infrastructure for GCP snapshot-based scanning with Qualys. The actual scanner invocation requires Qualys-specific components that must be obtained from Qualys support.

## Completed Components

### 1. Infrastructure
- Multi-project architecture (service + target projects)
- Terraform modules for all GCP resources
- IAM roles with least privilege
- VPC networking with Cloud NAT
- Managed Instance Groups for scanners
- Secret Manager for credentials
- Firestore for state management
- Pub/Sub for event routing

### 2. Orchestration
- Cloud Workflows for complete scan lifecycle
- Discovery workflow (find instances to scan)
- Snapshot creation workflow
- Scan execution workflow
- Cleanup workflow
- Main orchestration tying everything together

### 3. Automation
- Cloud Functions for instance discovery
- Cloud Scheduler for periodic scanning
- Automatic snapshot creation
- Automatic cleanup of old resources
- Label-based instance filtering

### 4. Deployment
- One-command deployment script (`deploy.sh`)
- Configuration examples
- API enablement automation
- Prerequisites checking

### 5. Documentation
- Architecture documentation
- Comprehensive README
- Configuration guides
- Troubleshooting section
- Cost optimization strategies

## Pending Components

### Scanner Integration with Qualys

The scanner instances successfully:
1. Receive scan requests
2. Create snapshots
3. Mount snapshot disks
4. Detect OS type
5. **Invoke Qualys scanner** - requires Qualys-specific binaries and configuration
6. **Upload results to QFlow** - requires validation of API endpoints and authentication

## Current Implementation Status

### Architecture Flow

```
1. Discovery (Operational)
   └─► Cloud Scheduler triggers every hour
       └─► Cloud Function lists instances across target projects
           └─► Filters by labels and last scan time
               └─► Triggers Cloud Workflow for each instance

2. Snapshot Creation (Operational)
   └─► Cloud Workflow creates disk snapshots
       └─► Shares snapshots with service project
           └─► Tracks status in Firestore

3. Scan Preparation (Operational)
   └─► Cloud Workflow creates temporary disk from snapshot
       └─► Attaches disk to scanner instance
           └─► Scanner instance mounts filesystem

4. Scan Execution (Requires Qualys Components)
   └─► Scanner instance runs /usr/local/bin/scan-snapshot.sh
       └─► Script attempts to:
           a) Download scanner scripts from QFlow API (if available)
           b) Execute Qualys scanner on mounted filesystem
           c) Generate results (ChangelistDB or similar)

5. Results Upload (Requires Validation)
   └─► Scanner uploads results to QFlow
       └─► Endpoint: {qualys_api}/qflow/snapshot/v1/upload
           └─► May require adjustment based on actual API

6. Cleanup (Operational)
   └─► Detach and delete temporary disks
       └─► Delete old snapshots
           └─► Remove stale scanner instances
```

## Scanner Script Strategy

### Current Approach: Bootstrap from QFlow API

Based on AWS implementation analysis, the scanner scripts use a **bootstrap-and-download** pattern:

```bash
# On scanner instance startup:
1. Bootstrap script runs
2. Fetches scanner scripts from QFlow API:
   - GET /qflow/gcp-snapshot/v1/scripts/scan-linux.sh
   - GET /qflow/gcp-snapshot/v1/scripts/scan-windows.sh
   - GET /qflow/gcp-snapshot/v1/scripts/upload-results.sh
3. If QFlow scripts not available:
   - Falls back to embedded placeholder scripts
   - Logs warning that actual scanning requires Qualys components
```

**Files:**
- `/scanner/scripts/bootstrap-scanner.sh` - Downloads scripts from QFlow
- `/scanner/scripts/scan-snapshot.sh` - Main scan orchestration
- `/terraform/modules/scanner/cloud-init.yaml` - Embeds fallback scripts

### What the Scanner Scripts Need to Do

1. **Mount the Snapshot** (Implemented)
   ```bash
   mount -o ro /dev/disk/by-id/google-$DISK_NAME /mnt/scan
   ```

2. **Run Qualys Scanner** (Requires clarification)
   ```bash
   # Option A: QScanner with VM snapshot mode?
   qscanner vmsnapshot --mount-path /mnt/scan --output /output

   # Option B: Qualys Cloud Agent offline mode?
   qualys-cloud-agent --offline-scan --target /mnt/scan

   # Option C: Downloaded from QFlow?
   bash /opt/qualys-scanner/scripts/scan-linux.sh /mnt/scan
   ```

3. **Upload Results** (Requires validation)
   ```bash
   curl -X POST \
     -H "Authorization: Bearer $TOKEN" \
     -F "file=@/output/changelist.db" \
     "$QUALYS_API/qflow/snapshot/v1/upload"
   ```

## Questions for Qualys

### Critical Path Items

1. **Is GCP snapshot scanning officially supported?**
   - If yes: Request GCP-specific documentation
   - If no: Request timeline or beta access

2. **What are the GCP QFlow API endpoints?**
   ```
   Known (from AWS): /qflow/aws-snapshot/v1/scripts/*
   GCP Equivalent: /qflow/gcp-snapshot/v1/scripts/*?
   ```

3. **What scanner binary/container should we use?**
   - [ ] qscanner from Docker Hub (`qualys/qscanner`)
   - [ ] Qualys Cloud Agent
   - [ ] Custom GCP scanner (download from Qualys portal)
   - [ ] Scripts downloaded from QFlow API

4. **What are the exact scanner commands?**
   ```bash
   # We assumed:
   qscanner vmsnapshot --mount-path /mnt/scan ...

   # But this may not exist. What's the actual command?
   ```

5. **What output format does QFlow expect?**
   - ChangelistDB file?
   - JSON?
   - Compressed archive?

### Nice-to-Have Information

- Recommended scanner instance size
- Expected scan durations
- Network bandwidth requirements
- Support for CMEK-encrypted disks
- Windows scanning specifics (NTFS mounting)

## Testing Without Qualys Scanner

You can still test the infrastructure:

### 1. Deploy Infrastructure
```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit with your values
./deploy.sh
```

### 2. Verify Orchestration
```bash
# Trigger discovery
gcloud pubsub topics publish qualys-discovery \
  --message='{"type":"manual"}' \
  --project=YOUR_PROJECT

# Watch workflow executions
gcloud workflows executions list \
  --workflow=qualys-main-orchestration

# Check logs
gcloud logging read 'resource.type="cloud_workflows"' --limit=50
```

### 3. Expected Output
- Instances discovered
- Snapshots created
- Disks attached to scanners
- Filesystems mounted
- Scanner runs placeholder script (logs warning)
- Resources cleaned up

## Path Forward

### Immediate Next Steps

1. **Contact Qualys Support**
   - Reference this implementation
   - Request GCP snapshot scanning components
   - Ask for technical account manager assignment

2. **Get Scanner Components**
   - Download/access Qualys GCP scanner
   - Obtain QFlow API documentation for GCP
   - Get sample scripts or reference implementation

3. **Integrate Scanner**
   - Replace placeholder scripts with real scanner
   - Test scan execution
   - Validate results upload to QFlow

4. **Production Rollout**
   - Start with small instance subset
   - Monitor costs and performance
   - Expand to full fleet

### Alternative: Adapt AWS Scanner

If GCP-specific scanner not available:

1. **Extract AWS Scanner**
   ```bash
   # From deployed AWS environment
   aws ssm start-session --target i-xxxxx
   tar czf /tmp/qualys-scanner.tar.gz /opt/qualys/*
   ```

2. **Adapt for GCP**
   - Replace AWS-specific calls (IMDSv2) with GCP metadata
   - Update disk device paths
   - Test on GCP Compute Engine

3. **Validate with Qualys**
   - Ensure license/entitlement covers GCP
   - Confirm results format compatible with QFlow

## Cost Estimates

Current infrastructure (without active scanning):

| Component | Monthly Cost |
|-----------|--------------|
| Scanner Instances (idle) | ~$50-100 |
| Firestore | ~$5-10 |
| Cloud Functions | ~$1-5 |
| Cloud Workflows | ~$1-5 |
| Pub/Sub | ~$1-5 |
| **Total (idle)** | **~$60-125/month** |

With active scanning (100-500 instances):

| Component | Monthly Cost |
|-----------|--------------|
| Scanner Instances (active) | $100-300 |
| Snapshot Storage | $50-200 |
| Network Egress | $20-100 |
| Other | $10-20 |
| **Total (active)** | **$180-620/month** |

## References

- [Qualys AWS Snapshot Scanning](https://docs.qualys.com/en/conn/latest/scans/snapshot-based_scan.htm)
- [Qualys QFlow Documentation](https://docs.qualys.com/en/qflow/latest/getting_started/overview.htm)
- [QScanner Docker Hub](https://hub.docker.com/r/qualys/qscanner)
- [GCP Compute Snapshots](https://cloud.google.com/compute/docs/disks/create-snapshots)
- [GCP Cloud Workflows](https://cloud.google.com/workflows/docs)

## Support

- **Qualys Support**: https://www.qualys.com/support/
- **Repository Issues**: [GitHub Issues](https://github.com/your-org/qualys-snapshot-gcp/issues)
- **GCP Support**: https://cloud.google.com/support

---

**Summary:** The infrastructure is production-ready. Once Qualys provides the GCP scanner components, integration can be completed.
