# Pub/Sub Module - Event routing and messaging

variable "service_project_id" {
  description = "Service project ID"
  type        = string
}

variable "function_service_account" {
  description = "Function service account email"
  type        = string
}

variable "labels" {
  description = "Labels to apply"
  type        = map(string)
}

# Discovery Topic - For instance discovery events
resource "google_pubsub_topic" "discovery" {
  name    = "qualys-discovery"
  project = var.service_project_id
  labels  = var.labels

  message_retention_duration = "86400s" # 24 hours
}

resource "google_pubsub_subscription" "discovery" {
  name    = "qualys-discovery-sub"
  topic   = google_pubsub_topic.discovery.name
  project = var.service_project_id
  labels  = var.labels

  ack_deadline_seconds = 600

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.discovery_dlq.id
    max_delivery_attempts = 5
  }
}

resource "google_pubsub_topic" "discovery_dlq" {
  name    = "qualys-discovery-dlq"
  project = var.service_project_id
  labels  = merge(var.labels, { type = "dead-letter-queue" })
}

# Snapshot Topic - For snapshot creation/scan events
resource "google_pubsub_topic" "snapshot" {
  name    = "qualys-snapshot"
  project = var.service_project_id
  labels  = var.labels

  message_retention_duration = "86400s"
}

resource "google_pubsub_subscription" "snapshot" {
  name    = "qualys-snapshot-sub"
  topic   = google_pubsub_topic.snapshot.name
  project = var.service_project_id
  labels  = var.labels

  ack_deadline_seconds = 600

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.snapshot_dlq.id
    max_delivery_attempts = 5
  }
}

resource "google_pubsub_topic" "snapshot_dlq" {
  name    = "qualys-snapshot-dlq"
  project = var.service_project_id
  labels  = merge(var.labels, { type = "dead-letter-queue" })
}

# Cleanup Topic - For resource cleanup events
resource "google_pubsub_topic" "cleanup" {
  name    = "qualys-cleanup"
  project = var.service_project_id
  labels  = var.labels

  message_retention_duration = "86400s"
}

resource "google_pubsub_subscription" "cleanup" {
  name    = "qualys-cleanup-sub"
  topic   = google_pubsub_topic.cleanup.name
  project = var.service_project_id
  labels  = var.labels

  ack_deadline_seconds = 300

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.cleanup_dlq.id
    max_delivery_attempts = 3
  }
}

resource "google_pubsub_topic" "cleanup_dlq" {
  name    = "qualys-cleanup-dlq"
  project = var.service_project_id
  labels  = merge(var.labels, { type = "dead-letter-queue" })
}

# Event Topic - For Compute Engine events (via Eventarc)
resource "google_pubsub_topic" "compute_events" {
  name    = "qualys-compute-events"
  project = var.service_project_id
  labels  = var.labels

  message_retention_duration = "86400s"
}

# IAM for topics
resource "google_pubsub_topic_iam_member" "discovery_publisher" {
  topic   = google_pubsub_topic.discovery.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${var.function_service_account}"
  project = var.service_project_id
}

resource "google_pubsub_topic_iam_member" "snapshot_publisher" {
  topic   = google_pubsub_topic.snapshot.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${var.function_service_account}"
  project = var.service_project_id
}

resource "google_pubsub_topic_iam_member" "cleanup_publisher" {
  topic   = google_pubsub_topic.cleanup.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${var.function_service_account}"
  project = var.service_project_id
}

# IAM for subscriptions
resource "google_pubsub_subscription_iam_member" "discovery_subscriber" {
  subscription = google_pubsub_subscription.discovery.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${var.function_service_account}"
  project      = var.service_project_id
}

resource "google_pubsub_subscription_iam_member" "snapshot_subscriber" {
  subscription = google_pubsub_subscription.snapshot.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${var.function_service_account}"
  project      = var.service_project_id
}

resource "google_pubsub_subscription_iam_member" "cleanup_subscriber" {
  subscription = google_pubsub_subscription.cleanup.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${var.function_service_account}"
  project      = var.service_project_id
}

output "discovery_topic_id" {
  description = "Discovery topic ID"
  value       = google_pubsub_topic.discovery.id
}

output "snapshot_topic_id" {
  description = "Snapshot topic ID"
  value       = google_pubsub_topic.snapshot.id
}

output "cleanup_topic_id" {
  description = "Cleanup topic ID"
  value       = google_pubsub_topic.cleanup.id
}

output "compute_events_topic_id" {
  description = "Compute events topic ID"
  value       = google_pubsub_topic.compute_events.id
}
