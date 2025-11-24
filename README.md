# Qualys Snapshot-Based Scanning for GCP

Agentless vulnerability scanning for Google Cloud Platform VM instances using Qualys qscanner.

## Overview

Automated security scanning that creates snapshots of VM disks, scans them offline, and uploads results to Qualys without impacting production workloads.

**Key Capabilities:**
- Agentless - no software installation on target VMs
- Zero workload impact - scans run on snapshot copies
- Multi-project scanning from a single service project
- Automated discovery and scheduling
- Cost-optimized with preemptible VMs and automatic cleanup

## Prerequisites

### GCP Requirements

1. **Service Project** - GCP project for scanner infrastructure
2. **Target Projects** - One or more projects with VMs to scan
3. **Permissions** - Project Editor on service project, Project Viewer on target projects
4. **Tools** - gcloud CLI, Terraform >= 1.5.0

### Qualys Requirements

1. **Qualys Subscription** - Active VMDR subscription
2. **Credentials** - Qualys POD and access token (from Qualys UI)
3. **QScanner Binary** - Bundled in `bin/qscanner.gz`

## Deployment

### 1. Extract QScanner

```bash
cd bin
gunzip qscanner.gz
chmod +x qscanner
cd ..
```

### 2. Configure

```bash
git clone <repository-url>
cd qualys-snapshot-gcp

# Copy and edit configuration
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
vim terraform/terraform.tfvars
```

**Required settings in `terraform.tfvars`:**

```hcl
service_project_id = "your-service-project-id"
target_project_ids = ["project-1", "project-2", "project-3"]

qualys_pod          = "US2"  # Your Qualys platform POD (US1, US2, US3, EU1, etc.)
qualys_access_token = "your-access-token"  # From Qualys UI

# Optional: customize scanning behavior
regions = ["us-central1", "us-east1"]
scanner_instances_per_region = 5
snapshot_retention_hours = 24
```

### 3. Deploy Infrastructure

```bash
# Authenticate
gcloud auth login
gcloud auth application-default login

# Deploy
./deploy.sh
```

The deployment creates:
- Managed instance groups for scanner VMs
- Cloud Workflows for orchestration
- Cloud Functions for discovery
- Firestore for state management
- IAM roles and networking

### 4. Install QScanner on Scanner Instances

After infrastructure deployment, install qscanner on each scanner instance:

```bash
# Get scanner instance names
gcloud compute instances list \
  --filter="labels.app=qualys-snapshot-scanner" \
  --project=YOUR_SERVICE_PROJECT

# For each scanner instance:
gcloud compute scp qscanner INSTANCE_NAME:/tmp/ \
  --zone=ZONE \
  --project=YOUR_SERVICE_PROJECT

gcloud compute ssh INSTANCE_NAME \
  --zone=ZONE \
  --project=YOUR_SERVICE_PROJECT \
  --command="sudo mkdir -p /opt/bin && sudo mv /tmp/qscanner /opt/bin/qscanner && sudo chmod +x /opt/bin/qscanner"
```

### 5. Verify Deployment

```bash
# Check workflows
gcloud workflows executions list \
  --workflow=qualys-main-orchestration \
  --project=YOUR_SERVICE_PROJECT

# View logs
gcloud logging read 'resource.type="cloud_workflows"' \
  --limit=20 \
  --project=YOUR_SERVICE_PROJECT

# Trigger manual scan
gcloud pubsub topics publish qualys-discovery \
  --message='{"type":"manual"}' \
  --project=YOUR_SERVICE_PROJECT
```

## Configuration

### Scan Settings

| Parameter | Default | Description |
|-----------|---------|-------------|
| `snapshot_retention_hours` | 24 | Snapshot retention before deletion (24-168) |
| `snapshot_refresh_interval_hours` | 24 | How often to rescan instances (24-168) |
| `polling_interval_minutes` | 60 | Discovery frequency (15-1440) |
| `scanner_instances_per_region` | 5 | Scanner VMs per region (1-50) |
| `scan_timeout_seconds` | 3600 | Maximum scan duration (60-3600) |

### Instance Filtering

Control which instances are scanned:

```hcl
# Only scan instances with ALL these labels
include_labels = {
  environment = "production"
  scan_enabled = "true"
}

# Skip instances with ANY of these labels
exclude_labels = {
  scan_disabled = "true"
}
```

### Multi-Region

Deploy scanners in multiple regions:

```hcl
regions = ["us-central1", "us-east1", "europe-west1"]
```

## Operations

### Monitoring

```bash
# List recent scans
gcloud workflows executions list --workflow=qualys-main-orchestration

# View execution details
gcloud workflows executions describe EXECUTION_ID \
  --workflow=qualys-main-orchestration

# Check scanner instance status
gcloud compute instances list \
  --filter="labels.app=qualys-snapshot-scanner"
```

### Troubleshooting

**No instances scanned:**
- Verify label filters match your VMs
- Check discovery function logs: `gcloud functions logs read qualys-discovery`
- Ensure target projects are configured correctly

**Scan failures:**
- Verify QScanner installed: SSH to scanner and check `/opt/bin/qscanner`
- Check Qualys credentials: `gcloud secrets versions access latest --secret=qualys-credentials`
- Review workflow logs for errors

**High costs:**
- Reduce `scanner_instances_per_region`
- Increase `snapshot_refresh_interval_hours`
- Decrease `snapshot_retention_hours`

### Manual Operations

Force immediate cleanup:
```bash
gcloud workflows execute qualys-cleanup \
  --data='{}' \
  --project=YOUR_SERVICE_PROJECT
```

Reset scan status for instance:
```bash
gcloud firestore documents delete \
  projects/YOUR_PROJECT/databases/(default)/documents/instances/INSTANCE_ID
```

## Cost Estimates

Monthly costs for 100-500 instances:

| Component | Monthly Cost |
|-----------|--------------|
| Scanner Instances (preemptible) | $50-150 |
| Snapshot Storage | $20-100 |
| Cloud Functions | $5-10 |
| Cloud Workflows | $5-10 |
| Firestore | $5-10 |
| **Total** | **$85-280** |

**Cost optimization:**
- Use preemptible VMs (enabled by default)
- Minimize snapshot retention period
- Adjust scan frequency based on needs
- Use regional resources only

## Security

### IAM
- Service accounts use principle of least privilege
- Scanner SA can only access service project resources
- Function SA has read-only access to target projects
- Cross-project access via explicit IAM bindings

### Network
- Scanner instances in dedicated VPC
- No external IPs (uses Cloud NAT)
- Firewall blocks all ingress traffic
- Egress limited to Qualys API endpoints

### Data
- Snapshots encrypted at rest with Google-managed keys
- Credentials stored in Secret Manager
- Automatic cleanup of temporary resources
- Audit logs in Cloud Logging

## Support

For issues and questions:
- GitHub Issues: Report bugs and feature requests
- Qualys Support: https://www.qualys.com/support/
- GCP Support: https://cloud.google.com/support

## License

[Add license]
