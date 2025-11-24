# GCP Snapshot-Based Scanning - Terraform Variables

variable "service_project_id" {
  description = "GCP project ID for the service account (where scanner infrastructure runs)"
  type        = string
}

variable "target_project_ids" {
  description = "List of GCP project IDs to scan (target projects with VM instances)"
  type        = list(string)
  default     = []
}

variable "region" {
  description = "Primary GCP region for deployment"
  type        = string
  default     = "us-central1"
}

variable "regions" {
  description = "List of GCP regions to deploy scanner infrastructure"
  type        = list(string)
  default     = ["us-central1"]
}

variable "qualys_pod" {
  description = "Qualys platform POD (e.g., US1, US2, US3, EU1, EU2)"
  type        = string
  validation {
    condition     = can(regex("^(US[1-4]|EU[1-2]|IN1|CA1|AU1|UK1)$", var.qualys_pod))
    error_message = "Qualys POD must be a valid platform identifier (US1-4, EU1-2, IN1, CA1, AU1, UK1)."
  }
}

variable "qualys_access_token" {
  description = "Qualys access token for qscanner authentication and QFlow integration"
  type        = string
  sensitive   = true
}

variable "qualys_api_url" {
  description = "Qualys API endpoint URL (optional, derived from POD if not specified)"
  type        = string
  default     = ""
}

variable "snapshot_retention_hours" {
  description = "How long to retain snapshots before deletion (hours)"
  type        = number
  default     = 24
  validation {
    condition     = var.snapshot_retention_hours >= 24 && var.snapshot_retention_hours <= 168
    error_message = "Snapshot retention must be between 24 and 168 hours."
  }
}

variable "snapshot_refresh_interval_hours" {
  description = "How often to rescan instances (hours)"
  type        = number
  default     = 24
  validation {
    condition     = var.snapshot_refresh_interval_hours >= 24 && var.snapshot_refresh_interval_hours <= 168
    error_message = "Snapshot refresh interval must be between 24 and 168 hours."
  }
}

variable "batch_trigger_duration_minutes" {
  description = "Batch event processing window (minutes)"
  type        = number
  default     = 10
  validation {
    condition     = var.batch_trigger_duration_minutes >= 5 && var.batch_trigger_duration_minutes <= 720
    error_message = "Batch trigger duration must be between 5 and 720 minutes."
  }
}

variable "polling_interval_minutes" {
  description = "Discovery polling frequency (minutes)"
  type        = number
  default     = 60
  validation {
    condition     = var.polling_interval_minutes >= 15 && var.polling_interval_minutes <= 1440
    error_message = "Polling interval must be between 15 and 1440 minutes."
  }
}

variable "scanner_instances_per_region" {
  description = "Number of scanner instances per region"
  type        = number
  default     = 5
  validation {
    condition     = var.scanner_instances_per_region >= 1 && var.scanner_instances_per_region <= 50
    error_message = "Scanner instances per region must be between 1 and 50."
  }
}

variable "scanner_machine_type" {
  description = "GCE machine type for scanner instances"
  type        = string
  default     = "n2-standard-4"
}

variable "scanner_disk_size_gb" {
  description = "Boot disk size for scanner instances (GB)"
  type        = number
  default     = 100
}

variable "use_preemptible_scanners" {
  description = "Use preemptible VMs for scanners (cost optimization)"
  type        = bool
  default     = true
}

variable "scan_timeout_seconds" {
  description = "Maximum scan duration (seconds)"
  type        = number
  default     = 3600
  validation {
    condition     = var.scan_timeout_seconds >= 60 && var.scan_timeout_seconds <= 3600
    error_message = "Scan timeout must be between 60 and 3600 seconds."
  }
}

variable "include_labels" {
  description = "Only scan instances with these labels (map of label_key = label_value)"
  type        = map(string)
  default     = {}
}

variable "exclude_labels" {
  description = "Skip instances with these labels (map of label_key = label_value)"
  type        = map(string)
  default     = {}
}

variable "enable_event_based_discovery" {
  description = "Enable event-based discovery using Eventarc"
  type        = bool
  default     = true
}

variable "enable_poll_based_discovery" {
  description = "Enable poll-based discovery using Cloud Scheduler"
  type        = bool
  default     = true
}

variable "qscanner_image" {
  description = "Container image for qscanner (in Artifact Registry)"
  type        = string
  default     = ""
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    app         = "qualys-snapshot-scanner"
    managed_by  = "terraform"
  }
}
