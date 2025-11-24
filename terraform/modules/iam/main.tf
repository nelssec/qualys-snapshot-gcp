# IAM Module - Cross-project permissions for snapshot scanning

variable "service_project_id" {
  description = "Service project ID"
  type        = string
}

variable "target_project_ids" {
  description = "Target project IDs"
  type        = list(string)
}

variable "scanner_service_account" {
  description = "Scanner service account email"
  type        = string
}

variable "function_service_account" {
  description = "Function service account email"
  type        = string
}

variable "workflow_service_account" {
  description = "Workflow service account email"
  type        = string
}

# Service Project IAM - Scanner SA
resource "google_project_iam_member" "scanner_compute_admin" {
  project = var.service_project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${var.scanner_service_account}"
}

resource "google_project_iam_member" "scanner_storage_admin" {
  project = var.service_project_id
  role    = "roles/compute.storageAdmin"
  member  = "serviceAccount:${var.scanner_service_account}"
}

resource "google_project_iam_member" "scanner_service_account_user" {
  project = var.service_project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${var.scanner_service_account}"
}

# Service Project IAM - Function SA
resource "google_project_iam_member" "function_compute_viewer" {
  project = var.service_project_id
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${var.function_service_account}"
}

resource "google_project_iam_member" "function_workflows_invoker" {
  project = var.service_project_id
  role    = "roles/workflows.invoker"
  member  = "serviceAccount:${var.function_service_account}"
}

resource "google_project_iam_member" "function_datastore_user" {
  project = var.service_project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${var.function_service_account}"
}

resource "google_project_iam_member" "function_pubsub_publisher" {
  project = var.service_project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${var.function_service_account}"
}

# Service Project IAM - Workflow SA
resource "google_project_iam_member" "workflow_compute_admin" {
  project = var.service_project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = "serviceAccount:${var.workflow_service_account}"
}

resource "google_project_iam_member" "workflow_storage_admin" {
  project = var.service_project_id
  role    = "roles/compute.storageAdmin"
  member  = "serviceAccount:${var.workflow_service_account}"
}

resource "google_project_iam_member" "workflow_service_account_user" {
  project = var.service_project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${var.workflow_service_account}"
}

resource "google_project_iam_member" "workflow_datastore_user" {
  project = var.service_project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${var.workflow_service_account}"
}

resource "google_project_iam_member" "workflow_logging_writer" {
  project = var.service_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${var.workflow_service_account}"
}

# Target Project IAM - Allow service project to access target projects
resource "google_project_iam_member" "target_compute_viewer" {
  for_each = toset(var.target_project_ids)

  project = each.value
  role    = "roles/compute.viewer"
  member  = "serviceAccount:${var.function_service_account}"
}

resource "google_project_iam_member" "target_snapshot_creator" {
  for_each = toset(var.target_project_ids)

  project = each.value
  role    = "roles/compute.storageAdmin"
  member  = "serviceAccount:${var.workflow_service_account}"
}

resource "google_project_iam_member" "target_snapshot_user" {
  for_each = toset(var.target_project_ids)

  project = each.value
  role    = "roles/compute.snapshotUser"
  member  = "serviceAccount:${var.scanner_service_account}"
}

# Custom role for minimal snapshot operations
resource "google_project_iam_custom_role" "snapshot_operator" {
  role_id     = "qualysSnapshotOperator"
  title       = "Qualys Snapshot Operator"
  description = "Minimal permissions for snapshot-based scanning"
  project     = var.service_project_id

  permissions = [
    "compute.disks.get",
    "compute.disks.list",
    "compute.disks.createSnapshot",
    "compute.snapshots.create",
    "compute.snapshots.get",
    "compute.snapshots.list",
    "compute.snapshots.delete",
    "compute.snapshots.setIamPolicy",
    "compute.instances.get",
    "compute.instances.list",
    "compute.instances.attachDisk",
    "compute.instances.detachDisk",
  ]
}

output "custom_role_id" {
  description = "Custom IAM role ID for snapshot operations"
  value       = google_project_iam_custom_role.snapshot_operator.id
}
