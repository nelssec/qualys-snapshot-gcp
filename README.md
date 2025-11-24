# Qualys Snapshot-Based Scanning for GCP

Zero-touch, agentless vulnerability scanning for Google Cloud Platform VM instances using Qualys qscanner and snapshot-based assessment.

## Overview

This solution provides automated, non-intrusive security scanning of GCP VM instances by:

1. **Creating snapshots** of VM disks without impacting running workloads
2. **Mounting snapshots** to dedicated scanner instances in a service project
3. **Scanning filesystems** with Qualys qscanner to detect vulnerabilities, secrets, and software composition
4. **Uploading results** to Qualys QFlow for vulnerability processing
5. **Cleaning up** temporary resources automatically

### Key Features

- ✅ **Agentless scanning** - No software installation on target VMs
- ✅ **Zero workload impact** - Scans run on snapshot copies
- ✅ **Multi-project support** - Service account model for bulk scanning
- ✅ **Automated orchestration** - Cloud Workflows handle the complete lifecycle
- ✅ **Event and poll-based discovery** - Captures new instances automatically
- ✅ **Cost-optimized** - Uses preemptible VMs and automatic cleanup
- ✅ **Security isolation** - Dedicated VPC for scanner infrastructure
- ✅ **Comprehensive scanning** - Vulnerabilities, secrets, and software composition analysis

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Target Projects                          │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐                   │
│  │ Project A│   │ Project B│   │ Project C│                   │
│  │          │   │          │   │          │                   │
│  │ VM Inst. │   │ VM Inst. │   │ VM Inst. │                   │
│  │    ↓     │   │    ↓     │   │    ↓     │                   │
│  │ Disks    │   │ Disks    │   │ Disks    │                   │
│  └────┬─────┘   └────┬─────┘   └────┬─────┘                   │
│       │              │              │                          │
│       └──────────────┴──────────────┘                          │
│                      │                                          │
│                 Snapshots                                       │
└─────────────────────┼───────────────────────────────────────────┘
                      │
                      ↓
┌─────────────────────────────────────────────────────────────────┐
│                      Service Project                            │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │               Cloud Workflows Orchestration              │  │
│  │   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐ │  │
│  │   │ Discover │→ │ Snapshot │→ │   Scan   │→ │Cleanup │ │  │
│  │   └──────────┘  └──────────┘  └──────────┘  └────────┘ │  │
│  └─────────────────────────────────────────────────────────┘  │
│                           ↓                                     │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │         Scanner Instance Group (Auto-scaling)            │  │
│  │   ┌──────────┐   ┌──────────┐   ┌──────────┐           │  │
│  │   │ Scanner  │   │ Scanner  │   │ Scanner  │           │  │
│  │   │ Instance │   │ Instance │   │ Instance │           │  │
│  │   │  + Disk  │   │  + Disk  │   │  + Disk  │           │  │
│  │   │ (mounted)│   │ (mounted)│   │ (mounted)│           │  │
│  │   └────┬─────┘   └────┬─────┘   └────┬─────┘           │  │
│  │        │              │              │                   │  │
│  │        └──────────────┴──────────────┘                   │  │
│  │                   qscanner                                │  │
│  │              (generates ChangelistDB)                     │  │
│  └─────────────────────────────────────────────────────────┘  │
│                           ↓                                     │
│                   Upload to QFlow                              │
└─────────────────────────────────────────────────────────────────┘
                            ↓
                    ┌───────────────┐
                    │  Qualys QFlow │
                    │  (Vuln Proc.) │
                    └───────────────┘
```

## Prerequisites

### Required Tools

- **Google Cloud SDK** (gcloud) - [Install](https://cloud.google.com/sdk/docs/install)
- **Terraform** >= 1.5.0 - [Install](https://www.terraform.io/downloads)
- **Python** 3.11+ (for Cloud Functions development)

### GCP Requirements

1. **Service Project**: A GCP project for hosting scanner infrastructure
2. **Target Projects**: One or more GCP projects with VM instances to scan
3. **Permissions**:
   - `Project Editor` or equivalent on service project
   - `Project Viewer` + specific IAM roles on target projects
4. **Enabled APIs**: The deployment script will enable required APIs

### Qualys Requirements

1. **Qualys Subscription**: Active Qualys VMDR subscription
2. **API Credentials**: Username and password for Qualys API
3. **Subscription Token**: QFlow integration token
4. **QScanner Access**: Container image access (provided by Qualys)

## Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/your-org/qualys-snapshot-gcp.git
cd qualys-snapshot-gcp
```

### 2. Configure Deployment

```bash
# Copy example configuration
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# Edit with your values
vim terraform/terraform.tfvars
```

**Required Configuration:**

```hcl
service_project_id = "my-service-project"
target_project_ids = ["project-1", "project-2"]

qualys_api_url            = "https://qualysapi.qualys.com"
qualys_username           = "your-username"
qualys_password           = "your-password"
qualys_subscription_token = "your-token"
```

### 3. Deploy Infrastructure

```bash
# Authenticate with GCP
gcloud auth login
gcloud auth application-default login

# Run deployment script
./deploy.sh
```

The deployment script will:
- ✅ Check prerequisites
- ✅ Enable required GCP APIs
- ✅ Create Terraform state bucket
- ✅ Deploy infrastructure with Terraform
- ✅ Deploy Cloud Functions
- ✅ Configure monitoring

### 4. Verify Deployment

```bash
# Check workflow executions
gcloud workflows executions list \
  --workflow=qualys-main-orchestration \
  --project=YOUR_SERVICE_PROJECT

# View logs
gcloud logging read 'resource.type="cloud_workflows"' \
  --limit=50 \
  --project=YOUR_SERVICE_PROJECT

# Check scanner instances
gcloud compute instances list \
  --filter="labels.app=qualys-snapshot-scanner" \
  --project=YOUR_SERVICE_PROJECT
```

### 5. Trigger Manual Scan

```bash
# Trigger discovery (scans will start automatically)
gcloud pubsub topics publish qualys-discovery \
  --message='{"type":"manual"}' \
  --project=YOUR_SERVICE_PROJECT
```

## Configuration

### Scan Settings

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| `snapshot_retention_hours` | 24 | 24-168 | Snapshot retention before deletion |
| `snapshot_refresh_interval_hours` | 24 | 24-168 | How often to rescan instances |
| `batch_trigger_duration_minutes` | 10 | 5-720 | Event batching window |
| `polling_interval_minutes` | 60 | 15-1440 | Discovery poll frequency |
| `scanner_instances_per_region` | 5 | 1-50 | Scanner instances per region |
| `scan_timeout_seconds` | 3600 | 60-3600 | Maximum scan duration |

### Instance Filtering

Control which instances are scanned using label-based filters:

```hcl
# Only scan instances with ALL these labels
include_labels = {
  environment = "production"
  scan        = "enabled"
}

# Skip instances with ANY of these labels
exclude_labels = {
  scan        = "disabled"
  backup-only = "true"
}
```

### Multi-Region Deployment

Deploy scanners in multiple regions for faster scanning:

```hcl
regions = ["us-central1", "us-east1", "europe-west1"]
```

## Operations

### Monitoring

View scan progress and results:

```bash
# Workflow executions
gcloud workflows executions list --workflow=qualys-main-orchestration

# Execution details
gcloud workflows executions describe EXECUTION_ID \
  --workflow=qualys-main-orchestration

# Logs
gcloud logging read 'resource.type="cloud_workflows"' --limit=100

# Scanner instance logs
gcloud logging read 'resource.type="gce_instance" AND labels.app="qualys-snapshot-scanner"'
```

### Troubleshooting

**No instances being scanned:**

1. Check discovery function logs:
   ```bash
   gcloud functions logs read qualys-discovery --limit=50
   ```

2. Verify label filters match your instances:
   ```bash
   gcloud compute instances list --format="table(name,labels)"
   ```

3. Check Firestore for discovered instances:
   ```bash
   gcloud firestore collections get instances
   ```

**Scan failures:**

1. Check workflow execution errors:
   ```bash
   gcloud workflows executions describe EXECUTION_ID
   ```

2. Verify scanner instances can reach Qualys API:
   ```bash
   # SSH to scanner instance
   gcloud compute ssh qualys-scanner-XXXX

   # Test connectivity
   curl -v https://qualysapi.qualys.com
   ```

3. Check Secret Manager credentials:
   ```bash
   gcloud secrets versions access latest --secret=qualys-credentials
   ```

**High costs:**

1. Reduce scanner instances:
   ```hcl
   scanner_instances_per_region = 2
   ```

2. Use preemptible VMs (default):
   ```hcl
   use_preemptible_scanners = true
   ```

3. Increase scan interval:
   ```hcl
   snapshot_refresh_interval_hours = 48
   ```

4. Reduce snapshot retention:
   ```hcl
   snapshot_retention_hours = 24
   ```

### Manual Operations

**Trigger immediate cleanup:**

```bash
gcloud workflows execute qualys-cleanup \
  --data='{}' \
  --project=YOUR_SERVICE_PROJECT
```

**Force rescan of specific instance:**

```bash
# Delete Firestore document to reset last scan time
gcloud firestore documents delete \
  projects/YOUR_PROJECT/databases/(default)/documents/instances/INSTANCE_ID
```

**View snapshot inventory:**

```bash
gcloud compute snapshots list \
  --filter="labels.app=qualys-snapshot-scanner"
```

## Cost Optimization

Estimated monthly costs (based on typical usage):

| Component | Cost Factor | Optimization |
|-----------|-------------|--------------|
| Scanner Instances | $50-200/month | Use preemptible VMs (-70%) |
| Snapshot Storage | $20-100/month | Reduce retention period |
| Cloud Functions | $5-20/month | Minimal (usage-based) |
| Cloud Workflows | $5-15/month | Minimal (execution-based) |
| Firestore | $5-10/month | Minimal (document-based) |
| Network Egress | $10-50/month | Use Private Google Access |

**Total**: ~$95-395/month for 100-500 instances

**Cost Reduction Tips:**

1. **Use preemptible scanners**: Save 70-90% on compute costs
2. **Minimize snapshot retention**: Delete after 24 hours
3. **Optimize scan frequency**: Scan less critical instances weekly
4. **Use regional resources**: Avoid cross-region snapshot copies
5. **Leverage autoscaling**: Scale down during off-peak hours

## Security Considerations

### Service Account Permissions

The solution follows the principle of least privilege:

- **Scanner SA**: Can create/delete disks and snapshots in service project only
- **Function SA**: Read-only access to target projects for discovery
- **Workflow SA**: Can create/manage compute resources for scanning

### Network Isolation

- Scanner instances run in dedicated VPC
- No external IPs on scanner instances (uses Cloud NAT)
- Firewall rules restrict all ingress traffic
- Egress limited to Qualys API endpoints

### Data Protection

- Snapshots encrypted at rest with Google-managed keys
- Qualys credentials stored in Secret Manager
- Snapshots marked with retention labels
- Automatic cleanup prevents data accumulation

### Compliance

- **PCI DSS**: Agentless scanning reduces compliance scope
- **HIPAA**: No PHI accessed (snapshots scanned offline)
- **SOC 2**: Audit logs in Cloud Logging
- **GDPR**: Data retention policies configurable

## Architecture Decisions

### Why Cloud Workflows?

- Native GCP orchestration (no external dependencies)
- Built-in retry and error handling
- Parallel execution support
- Low cost (pay per execution)
- Easy debugging with execution history

### Why Firestore?

- Real-time updates for scan status
- Powerful querying for filtering instances
- Automatic scaling
- Low latency for state lookups
- Native GCP integration

### Why Managed Instance Groups?

- Auto-scaling based on scan queue depth
- Auto-healing for failed instances
- Rolling updates for scanner image upgrades
- Multi-zone deployment for reliability
- Integration with load balancing (future)

## Limitations

1. **Encrypted Disks**: Currently supports Google-managed encryption keys only. Customer-managed encryption keys (CMEK) require additional setup.

2. **Scan Scope**: Scans boot disks only. Additional data disks not currently scanned.

3. **Windows Support**: Requires Windows scanner instances with NTFS mounting support.

4. **Cross-Region Snapshots**: Snapshots must be in same region as scanner instances for optimal performance.

5. **Large Disks**: Very large disks (>1TB) may hit scan timeout limits.

## Roadmap

- [ ] **CMEK Support**: Handle customer-managed encryption keys
- [ ] **Data Disk Scanning**: Scan additional attached disks
- [ ] **Event-Based Discovery**: Real-time instance detection via Eventarc
- [ ] **Cloud Run Scanners**: Serverless scanner execution
- [ ] **Multi-Region Snapshots**: Cross-region scanning support
- [ ] **Security Command Center Integration**: Export findings to GCP SCC
- [ ] **Scan Sampling**: Percentage-based scanning for large fleets
- [ ] **Volume Filtering**: Skip specific disks based on labels

## References

- [AWS Snapshot Based Assessment (Qualys TotalCloud)](https://github.com/Qualys/TotalCloud)
- [Qualys Zero-Touch Snapshot Scanning for AWS](https://docs.qualys.com/en/conn/latest/scans/snapshot-based_scan.htm)
- [Qualys Zero-Touch Snapshot Scanning for Azure](https://docs.qualys.com/en/conn/latest/scans/configure_zero-touch_snapshot-based_scan_for_azure.htm)
- [Qualys QFlow Documentation](https://docs.qualys.com/en/qflow/latest/getting_started/overview.htm)
- [GCP Compute Engine Snapshots](https://cloud.google.com/compute/docs/disks/create-snapshots)
- [GCP Cloud Workflows](https://cloud.google.com/workflows/docs)

## Contributing

Contributions welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[Add your license here]

## Support

For issues and questions:
- **GitHub Issues**: [Report a bug](https://github.com/your-org/qualys-snapshot-gcp/issues)
- **Qualys Support**: [Contact Qualys](https://www.qualys.com/support/)
- **GCP Support**: [Google Cloud Support](https://cloud.google.com/support)
