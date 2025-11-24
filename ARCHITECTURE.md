# GCP Snapshot-Based Scanning Architecture

## Overview

This document outlines the architecture for Qualys snapshot-based vulnerability scanning in Google Cloud Platform.

## Key Concepts

### QFlow-Orchestrated Scanning
- **qscanner** vmsnapshot/winvmsnapshot commands are specifically designed for QFlow orchestrated VM snapshots
- QScanner performs data collection and generates **ChangelistDB**
- QFlow is responsible for uploading ChangelistDB to Qualys backend for vulnerability processing
- **No vulnerability reporting** is done by QScanner directly

## Architecture Components

### Multi-Project Model

- **Service Project**: Contains orchestration infrastructure and scanning resources
- **Target Projects**: GCP projects containing VM instances to be scanned

### Core GCP Services

| Service | Purpose |
|---------|---------|
| Cloud Workflows | Orchestration state machines |
| Cloud Functions | Event-driven compute for discovery |
| Pub/Sub + Eventarc | Event routing and triggers |
| Firestore | Configuration and state storage |
| Cloud Scheduler | Scheduled discovery tasks |
| Compute Engine | Scanner instance execution |
| Secret Manager | Qualys credentials storage |

## Workflow Design

### 1. Discovery Phase

**Event-Based Discovery:**
- Eventarc monitors Compute Engine audit logs for VM lifecycle events
- Events published to Pub/Sub topics
- Cloud Functions triggered to process instance changes

**Poll-Based Discovery:**
- Cloud Scheduler triggers periodic polling (default: 1 hour)
- Cloud Function queries Compute Engine API for instances across target projects
- Filters based on labels/tags

### 2. Snapshot Creation

```
Cloud Workflow: CreateSnapshot
├── Input: VM instance metadata
├── Step 1: Create disk snapshots (gcloud compute disks snapshot)
├── Step 2: Share snapshot with service project (IAM permissions)
├── Step 3: Wait for snapshot completion
└── Output: Snapshot resource names
```

**GCP APIs Used:**
- `compute.snapshots.create`
- `compute.snapshots.get`
- `compute.snapshots.setIamPolicy`

### 3. Snapshot Scanning

```
Cloud Workflow: ScanSnapshot
├── Input: Snapshot resource names
├── Step 1: Create temporary disk from snapshot
├── Step 2: Attach disk to scanner instance
├── Step 3: Mount disk in scanner instance
├── Step 4: Run qscanner vmsnapshot/winvmsnapshot
├── Step 5: Generate ChangelistDB
├── Step 6: Upload ChangelistDB to QFlow backend
├── Step 7: Unmount and detach disk
└── Step 8: Cleanup temporary resources
```

**Scanner Instance:**
- Compute Engine VM with qscanner installed
- Pre-configured with Qualys credentials
- Supports both Linux (vmsnapshot) and Windows (winvmsnapshot)
- Can be scaled with Managed Instance Groups

### 4. Cleanup Phase

```
Cloud Workflow: Cleanup
├── Input: Resources to clean
├── Step 1: Detach disks from scanner instances
├── Step 2: Delete temporary disks
├── Step 3: Delete snapshots (if retention period expired)
└── Output: Cleanup confirmation
```

## Resource Lifecycle

### Scanner Instance Pool
- **Managed Instance Group** with autoscaling
- Instances created on-demand when snapshots need scanning
- Configurable: 1-50 instances per region
- Instances tagged with `app: qualys-snapshot-scanner`

### Snapshot Retention
- Configurable retention period: 24-168 hours (default: 24 hours)
- Snapshots automatically deleted after retention period
- Cleanup handled by scheduled Cloud Function

## Configuration Parameters

### Scan Settings
| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| Snapshot Refresh Interval | 24 hours | 24-168 hours | How often to rescan instances |
| Batch Trigger Duration | 10 minutes | 5-720 minutes | Batch event processing window |
| Scanner Instances Per Region | 5 | 1-50 | Concurrent scanning capacity |
| Scan Timeout | 120 seconds | 60-600 seconds | Maximum scan duration |
| Polling Interval | 60 minutes | 15-1440 minutes | Discovery polling frequency |

### Instance Filtering
- **Include Labels**: Instances must have specific labels to be scanned
- **Exclude Labels**: Skip instances with specific labels
- **Project Filtering**: Whitelist/blacklist target projects

## Security Model

### Service Account Permissions

**Service Project Service Account:**
- `compute.snapshots.list`
- `compute.snapshots.get`
- `compute.disks.create`
- `compute.disks.delete`
- `compute.instances.attachDisk`
- `compute.instances.detachDisk`

**Target Project Service Account:**
- `compute.instances.list`
- `compute.instances.get`
- `compute.disks.createSnapshot`
- `compute.snapshots.create`
- `compute.snapshots.setIamPolicy`

### Cross-Project Access
- Service account from service project granted `compute.snapshotUser` role in target projects
- IAM bindings established during deployment
- Minimal permissions following principle of least privilege

## Deployment

### Prerequisites
1. GCP projects (service + target)
2. Enabled APIs:
   - Compute Engine API
   - Cloud Functions API
   - Cloud Workflows API
   - Pub/Sub API
   - Firestore API
   - Cloud Scheduler API
3. Qualys subscription and credentials
4. qscanner container image in Artifact Registry

### Deployment Steps
1. Configure `terraform.tfvars` with project settings
2. Run `terraform init`
3. Run `terraform plan` to review resources
4. Run `terraform apply` to deploy infrastructure
5. Configure Qualys QFlow integration
6. Verify scanner instance can communicate with Qualys backend

## Cost Optimization

### Snapshot Storage
- Incremental snapshots reduce storage costs
- Automatic cleanup after retention period
- Use regional snapshots (cheaper than multi-regional)

### Compute Costs
- Scanner instances only run when needed
- Preemptible VMs for scanner instances (70-90% cost reduction)
- Autoscaling based on scan queue depth

### Network Costs
- Scanner instances in same region as snapshots
- Private Google Access for Qualys API communication
- Cloud NAT for internet access (if needed)

## Monitoring and Observability

### Cloud Logging
- All workflow executions logged
- Scanner instance logs aggregated
- Audit logs for resource access

### Cloud Monitoring
- Scan completion metrics
- Error rates and types
- Resource utilization
- Snapshot age and retention

### Alerting
- Failed scans
- Stale snapshots
- Scanner instance failures
- Quota limits approaching

## References

- [Qualys QFlow Documentation](https://docs.qualys.com/en/qflow/latest/getting_started/overview.htm)
- [GCP Compute Engine Snapshots](https://cloud.google.com/compute/docs/disks/create-snapshots)
- [GCP Cloud Workflows](https://cloud.google.com/workflows/docs)
