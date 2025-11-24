# Firestore Module - State and configuration storage

variable "service_project_id" {
  description = "Service project ID"
  type        = string
}

variable "region" {
  description = "Region for Firestore"
  type        = string
}

variable "labels" {
  description = "Labels to apply"
  type        = map(string)
}

# Firestore Database
resource "google_firestore_database" "scanner_db" {
  project     = var.service_project_id
  name        = "(default)"
  location_id = var.region
  type        = "FIRESTORE_NATIVE"

  lifecycle {
    prevent_destroy = false
  }
}

# Firestore Indexes for efficient queries
resource "google_firestore_index" "instance_last_scanned" {
  project    = var.service_project_id
  database   = google_firestore_database.scanner_db.name
  collection = "instances"

  fields {
    field_path = "lastScanned"
    order      = "ASCENDING"
  }

  fields {
    field_path = "projectId"
    order      = "ASCENDING"
  }

  fields {
    field_path = "__name__"
    order      = "ASCENDING"
  }
}

resource "google_firestore_index" "instance_status" {
  project    = var.service_project_id
  database   = google_firestore_database.scanner_db.name
  collection = "instances"

  fields {
    field_path = "scanStatus"
    order      = "ASCENDING"
  }

  fields {
    field_path = "lastScanned"
    order      = "ASCENDING"
  }

  fields {
    field_path = "__name__"
    order      = "ASCENDING"
  }
}

resource "google_firestore_index" "snapshot_age" {
  project    = var.service_project_id
  database   = google_firestore_database.scanner_db.name
  collection = "snapshots"

  fields {
    field_path = "createdAt"
    order      = "ASCENDING"
  }

  fields {
    field_path = "status"
    order      = "ASCENDING"
  }

  fields {
    field_path = "__name__"
    order      = "ASCENDING"
  }
}

output "database_name" {
  description = "Firestore database name"
  value       = google_firestore_database.scanner_db.name
}

output "database_id" {
  description = "Firestore database ID"
  value       = google_firestore_database.scanner_db.id
}
