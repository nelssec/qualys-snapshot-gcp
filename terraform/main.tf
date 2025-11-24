# GCP Snapshot-Based Scanning - Main Terraform Configuration

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    # Configure backend in terraform.tfvars or via CLI
    # bucket = "your-terraform-state-bucket"
    # prefix = "qualys-snapshot-scanner"
  }
}

provider "google" {
  project = var.service_project_id
  region  = var.region
}

provider "google-beta" {
  project = var.service_project_id
  region  = var.region
}

# Local variables
locals {
  # Map Qualys POD to API URL
  # Reference: https://www.qualys.com/platform-identification/
  qualys_api_urls = {
    US1 = "https://qualysapi.qualys.com"
    US2 = "https://qualysapi.qg2.apps.qualys.com"
    US3 = "https://qualysapi.qg3.apps.qualys.com"
    US4 = "https://qualysapi.qg4.apps.qualys.com"
    EU1 = "https://qualysapi.qg1.apps.qualys.eu"
    EU2 = "https://qualysapi.qg2.apps.qualys.eu"
    IN1 = "https://qualysapi.qg1.apps.qualys.in"
    CA1 = "https://qualysapi.qg1.apps.qualys.ca"
    AU1 = "https://qualysapi.qg1.apps.qualys.com.au"
    UK1 = "https://qualysapi.qg1.apps.qualys.co.uk"
  }

  qualys_api_url = var.qualys_api_url != "" ? var.qualys_api_url : local.qualys_api_urls[var.qualys_pod]
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "cloudfunctions.googleapis.com",
    "workflows.googleapis.com",
    "pubsub.googleapis.com",
    "firestore.googleapis.com",
    "cloudscheduler.googleapis.com",
    "eventarc.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ])

  project = var.service_project_id
  service = each.value

  disable_on_destroy = false
}

# Service Account for Scanner Infrastructure
resource "google_service_account" "scanner_service_account" {
  account_id   = "qualys-scanner-sa"
  display_name = "Qualys Snapshot Scanner Service Account"
  description  = "Service account for Qualys snapshot-based scanning infrastructure"
  project      = var.service_project_id
}

# Service Account for Cloud Functions
resource "google_service_account" "function_service_account" {
  account_id   = "qualys-function-sa"
  display_name = "Qualys Cloud Functions Service Account"
  description  = "Service account for Qualys Cloud Functions"
  project      = var.service_project_id
}

# Service Account for Cloud Workflows
resource "google_service_account" "workflow_service_account" {
  account_id   = "qualys-workflow-sa"
  display_name = "Qualys Cloud Workflows Service Account"
  description  = "Service account for Qualys Cloud Workflows"
  project      = var.service_project_id
}

# Store Qualys credentials in Secret Manager
resource "google_secret_manager_secret" "qualys_credentials" {
  secret_id = "qualys-credentials"
  project   = var.service_project_id

  replication {
    auto {}
  }

  labels = var.labels

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "qualys_credentials" {
  secret = google_secret_manager_secret.qualys_credentials.id

  secret_data = jsonencode({
    pod          = var.qualys_pod
    access_token = var.qualys_access_token
    api_url      = local.qualys_api_url
  })
}

# Grant access to secret
resource "google_secret_manager_secret_iam_member" "scanner_access" {
  secret_id = google_secret_manager_secret.qualys_credentials.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.scanner_service_account.email}"
}

resource "google_secret_manager_secret_iam_member" "function_access" {
  secret_id = google_secret_manager_secret.qualys_credentials.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.function_service_account.email}"
}

resource "google_secret_manager_secret_iam_member" "workflow_access" {
  secret_id = google_secret_manager_secret.qualys_credentials.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.workflow_service_account.email}"
}

# IAM Module - Cross-project permissions
module "iam" {
  source = "./modules/iam"

  service_project_id        = var.service_project_id
  target_project_ids        = var.target_project_ids
  scanner_service_account   = google_service_account.scanner_service_account.email
  function_service_account  = google_service_account.function_service_account.email
  workflow_service_account  = google_service_account.workflow_service_account.email
}

# Firestore Module - State and configuration storage
module "firestore" {
  source = "./modules/firestore"

  service_project_id = var.service_project_id
  region             = var.region
  labels             = var.labels

  depends_on = [google_project_service.required_apis]
}

# Pub/Sub Module - Event routing
module "pubsub" {
  source = "./modules/pubsub"

  service_project_id       = var.service_project_id
  function_service_account = google_service_account.function_service_account.email
  labels                   = var.labels

  depends_on = [google_project_service.required_apis]
}

# Scanner Module - Compute instances for scanning
module "scanner" {
  source = "./modules/scanner"

  service_project_id         = var.service_project_id
  regions                    = var.regions
  scanner_service_account    = google_service_account.scanner_service_account.email
  scanner_machine_type       = var.scanner_machine_type
  scanner_disk_size_gb       = var.scanner_disk_size_gb
  scanner_instances_per_region = var.scanner_instances_per_region
  use_preemptible_scanners   = var.use_preemptible_scanners
  qscanner_image             = var.qscanner_image
  qualys_secret_name         = google_secret_manager_secret.qualys_credentials.secret_id
  labels                     = var.labels

  depends_on = [
    google_project_service.required_apis,
    google_secret_manager_secret_version.qualys_credentials
  ]
}

# Workflows Module - Cloud Workflows for orchestration
module "workflows" {
  source = "./modules/workflows"

  service_project_id          = var.service_project_id
  region                      = var.region
  workflow_service_account    = google_service_account.workflow_service_account.email
  scanner_instance_template   = module.scanner.instance_template_self_links
  scan_timeout_seconds        = var.scan_timeout_seconds
  snapshot_retention_hours    = var.snapshot_retention_hours
  labels                      = var.labels

  depends_on = [google_project_service.required_apis]
}

# Cloud Functions
# Discovery Function - Polls for instances to scan
resource "google_storage_bucket" "function_source" {
  name     = "${var.service_project_id}-qualys-functions"
  location = var.region
  project  = var.service_project_id

  uniform_bucket_level_access = true
  labels                      = var.labels

  depends_on = [google_project_service.required_apis]
}

# Cloud Scheduler for poll-based discovery
resource "google_cloud_scheduler_job" "discovery_poll" {
  count = var.enable_poll_based_discovery ? 1 : 0

  name             = "qualys-discovery-poll"
  description      = "Periodic discovery of instances to scan"
  schedule         = "*/${var.polling_interval_minutes} * * * *"
  time_zone        = "UTC"
  project          = var.service_project_id
  region           = var.region

  pubsub_target {
    topic_name = module.pubsub.discovery_topic_id
    data       = base64encode(jsonencode({
      type = "poll"
      target_projects = var.target_project_ids
    }))
  }

  depends_on = [google_project_service.required_apis]
}

# Outputs
output "scanner_service_account_email" {
  description = "Email of the scanner service account"
  value       = google_service_account.scanner_service_account.email
}

output "function_service_account_email" {
  description = "Email of the function service account"
  value       = google_service_account.function_service_account.email
}

output "workflow_service_account_email" {
  description = "Email of the workflow service account"
  value       = google_service_account.workflow_service_account.email
}

output "discovery_topic_id" {
  description = "Pub/Sub topic ID for discovery events"
  value       = module.pubsub.discovery_topic_id
}

output "scan_workflow_id" {
  description = "Cloud Workflow ID for scanning"
  value       = module.workflows.scan_workflow_id
}
