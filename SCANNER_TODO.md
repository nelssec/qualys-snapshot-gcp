# Scanner Implementation - TO BE COMPLETED

## Status: INCOMPLETE - REQUIRES QUALYS INPUT

This document outlines what needs to be provided by Qualys to complete the GCP snapshot scanning implementation.

## Current Gap

The infrastructure and orchestration are complete, but the actual scanner invocation mechanism requires Qualys-specific components that are not publicly documented.

## What We Need from Qualys

### 1. Scanner Software

**Question:** What is the actual scanner component for GCP VM snapshot scanning?

**Possible options:**
- [ ] A special build of qscanner for VM snapshots
- [ ] A separate Qualys Cloud Agent binary
- [ ] A custom container image from Qualys private registry
- [ ] SSM/script-based scanning using Qualys API

**Required Information:**
- Download location or container registry URL
- Authentication mechanism (Qualys credentials? Subscription token?)
- Supported platforms (Linux amd64/arm64, Windows, etc.)
- License/entitlement requirements

### 2. Scan Invocation

**Question:** How do we invoke the scanner on a mounted snapshot filesystem?

**Current assumption (requires validation):**
```bash
# Linux
qscanner vmsnapshot \
  --mount-path /mnt/snapshot \
  --output-dir /output \
  --qualys-url https://qualysapi.qualys.com \
  --auth-token $TOKEN

# Windows
qscanner winvmsnapshot \
  --mount-path /mnt/snapshot \
  --output-dir /output \
  --qualys-url https://qualysapi.qualys.com \
  --auth-token $TOKEN
```

**What We Need:**
- Exact command-line syntax
- Required parameters
- Authentication method
- Configuration file format (if any)
- Environment variables needed

### 3. Output and QFlow Integration

**Question:** How are scan results uploaded to QFlow?

**Current assumption (requires validation):**
```bash
# Scanner generates: /output/changelist.db
# Upload via:
curl -X POST \
  -H "Authorization: Bearer $SUBSCRIPTION_TOKEN" \
  -F "file=@/output/changelist.db" \
  -F "snapshot_name=$SNAPSHOT_NAME" \
  -F "instance_id=$INSTANCE_ID" \
  https://qualysapi.qualys.com/qflow/snapshot/v1/upload
```

**What We Need:**
- Output file format and location
- QFlow API endpoint for snapshot results
- Authentication headers and parameters
- Required metadata fields
- Compression/chunking requirements (for large files)

### 4. OS Detection

**Question:** How do we detect Linux vs Windows for choosing vmsnapshot vs winvmsnapshot?

**Possible options:**
- [ ] Inspect mounted filesystem (/etc, /Windows, etc.)
- [ ] Use GCP instance metadata
- [ ] Try Linux first, fallback to Windows
- [ ] Separate workflows for each OS type

### 5. Error Handling

**Question:** What are the expected error codes and how should we handle them?

**Required information:**
- Exit codes and their meanings
- Retry logic recommendations
- Timeout values
- Partial scan handling

## Alternative Approaches

If the above information is not available, we could explore:

### Option A: API-Based Scanning
```bash
# Instead of running a scanner binary, make API calls
# to Qualys with snapshot metadata
curl -X POST https://qualysapi.qualys.com/api/2.0/snapshot/scan \
  -H "Authorization: Basic $CREDENTIALS" \
  -d "snapshot_id=$SNAPSHOT_ID" \
  -d "project_id=$PROJECT_ID"
```

### Option B: Qualys Cloud Agent
```bash
# Use existing Qualys Cloud Agent in "offline mode"
qualys-cloud-agent --offline-scan \
  --target /mnt/snapshot \
  --output /output/results.json
```

### Option C: Remote Scanning via Qualys
```bash
# Mount snapshot, expose via NFS/SMB
# Let Qualys Virtual Scanner Appliance scan it remotely
# (Less ideal for security and performance)
```

## Questions for Qualys Support

When contacting Qualys, ask for:

1. **Is GCP snapshot-based scanning officially supported?**
   - If yes: Request GCP-specific documentation
   - If no: Request timeline or beta access

2. **Can we adapt the AWS snapshot scanning method to GCP?**
   - Request AWS scanner AMI details
   - Ask if scanner can run on GCP Compute Engine

3. **What's the scanner distribution method?**
   - Docker Hub? Qualys portal download? API endpoint?

4. **Sample implementation or reference?**
   - Working example for AWS/Azure we can adapt
   - Integration test environment

5. **Support engagement**
   - Technical account manager contact
   - Professional services for implementation

## Workaround: Manual Testing

Until we get Qualys input, here's how to test the infrastructure:

1. **Deploy the infrastructure** (everything except scanner invocation works)
2. **Create a test scanner script** that just logs and returns success
3. **Verify the orchestration** works end-to-end
4. **Replace the placeholder** once we have real scanner details

Example test script:
```bash
#!/bin/bash
# test-scanner.sh - Placeholder for actual Qualys scanner

MOUNT_POINT="$1"
OUTPUT_DIR="$2"

echo "[TEST] Scanning mounted filesystem at $MOUNT_POINT"
ls -la "$MOUNT_POINT"

# Generate fake changelist.db
echo "FAKE_SCAN_RESULTS" > "$OUTPUT_DIR/changelist.db"

echo "[TEST] Scan complete - generated fake results"
exit 0
```

## Contact Information

**Qualys Support:**
- Support Portal: https://www.qualys.com/support/
- Documentation: https://docs.qualys.com/
- Community: https://community.qualys.com/

**Request Specifically:**
- "GCP VM snapshot-based scanning implementation guide"
- "QScanner documentation for filesystem scanning"
- "QFlow snapshot upload API specification"

---

**Last Updated:** 2025-11-24
**Status:** Awaiting Qualys input
**Blocker:** Scanner invocation mechanism not documented
