# Workflows Module - Cloud Workflows for orchestration

variable "service_project_id" {
  description = "Service project ID"
  type        = string
}

variable "region" {
  description = "Region for workflows"
  type        = string
}

variable "workflow_service_account" {
  description = "Workflow service account email"
  type        = string
}

variable "scanner_instance_template" {
  description = "Scanner instance template self links"
  type        = map(string)
}

variable "scan_timeout_seconds" {
  description = "Scan timeout in seconds"
  type        = number
}

variable "snapshot_retention_hours" {
  description = "Snapshot retention in hours"
  type        = number
}

variable "labels" {
  description = "Labels to apply"
  type        = map(string)
}

# Workflow: Create Snapshot
resource "google_workflows_workflow" "create_snapshot" {
  name            = "qualys-create-snapshot"
  project         = var.service_project_id
  region          = var.region
  description     = "Create snapshot from VM instance disk"
  service_account = var.workflow_service_account
  labels          = var.labels

  source_contents = file("${path.module}/create-snapshot.yaml")
}

# Workflow: Scan Snapshot
resource "google_workflows_workflow" "scan_snapshot" {
  name            = "qualys-scan-snapshot"
  project         = var.service_project_id
  region          = var.region
  description     = "Scan snapshot with Qualys qscanner"
  service_account = var.workflow_service_account
  labels          = var.labels

  source_contents = templatefile("${path.module}/scan-snapshot.yaml", {
    scan_timeout_seconds = var.scan_timeout_seconds
  })
}

# Workflow: Cleanup Resources
resource "google_workflows_workflow" "cleanup" {
  name            = "qualys-cleanup"
  project         = var.service_project_id
  region          = var.region
  description     = "Cleanup temporary snapshots and disks"
  service_account = var.workflow_service_account
  labels          = var.labels

  source_contents = templatefile("${path.module}/cleanup.yaml", {
    retention_hours = var.snapshot_retention_hours
  })
}

# Workflow: Main Orchestration
resource "google_workflows_workflow" "main_orchestration" {
  name            = "qualys-main-orchestration"
  project         = var.service_project_id
  region          = var.region
  description     = "Main orchestration workflow for snapshot scanning"
  service_account = var.workflow_service_account
  labels          = var.labels

  source_contents = templatefile("${path.module}/main-orchestration.yaml", {
    create_snapshot_workflow = google_workflows_workflow.create_snapshot.id
    scan_snapshot_workflow   = google_workflows_workflow.scan_snapshot.id
    cleanup_workflow         = google_workflows_workflow.cleanup.id
  })
}

output "create_snapshot_workflow_id" {
  description = "Create snapshot workflow ID"
  value       = google_workflows_workflow.create_snapshot.id
}

output "scan_workflow_id" {
  description = "Scan snapshot workflow ID"
  value       = google_workflows_workflow.scan_snapshot.id
}

output "cleanup_workflow_id" {
  description = "Cleanup workflow ID"
  value       = google_workflows_workflow.cleanup.id
}

output "main_orchestration_workflow_id" {
  description = "Main orchestration workflow ID"
  value       = google_workflows_workflow.main_orchestration.id
}
