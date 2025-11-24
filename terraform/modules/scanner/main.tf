# Scanner Module - Compute instances for scanning snapshots

variable "service_project_id" {
  description = "Service project ID"
  type        = string
}

variable "regions" {
  description = "Regions to deploy scanner instances"
  type        = list(string)
}

variable "scanner_service_account" {
  description = "Scanner service account email"
  type        = string
}

variable "scanner_machine_type" {
  description = "Machine type for scanner instances"
  type        = string
}

variable "scanner_disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
}

variable "scanner_instances_per_region" {
  description = "Number of scanner instances per region"
  type        = number
}

variable "use_preemptible_scanners" {
  description = "Use preemptible VMs"
  type        = bool
}

variable "qscanner_image" {
  description = "QScanner container image"
  type        = string
}

variable "qualys_secret_name" {
  description = "Secret Manager secret name for Qualys credentials"
  type        = string
}

variable "labels" {
  description = "Labels to apply"
  type        = map(string)
}

# VPC Network for Scanner Instances
resource "google_compute_network" "scanner_network" {
  name                    = "qualys-scanner-network"
  project                 = var.service_project_id
  auto_create_subnetworks = false
}

# Subnets for each region
resource "google_compute_subnetwork" "scanner_subnet" {
  for_each = toset(var.regions)

  name          = "qualys-scanner-subnet-${each.value}"
  ip_cidr_range = "10.${index(var.regions, each.value)}.0.0/24"
  region        = each.value
  network       = google_compute_network.scanner_network.id
  project       = var.service_project_id

  private_ip_google_access = true
}

# Cloud NAT for internet access (if needed for Qualys API)
resource "google_compute_router" "scanner_router" {
  for_each = toset(var.regions)

  name    = "qualys-scanner-router-${each.value}"
  region  = each.value
  network = google_compute_network.scanner_network.id
  project = var.service_project_id
}

resource "google_compute_router_nat" "scanner_nat" {
  for_each = toset(var.regions)

  name                               = "qualys-scanner-nat-${each.value}"
  router                             = google_compute_router.scanner_router[each.value].name
  region                             = each.value
  nat_ip_allocate_option            = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  project                            = var.service_project_id

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Firewall Rules
resource "google_compute_firewall" "scanner_egress_qualys" {
  name    = "qualys-scanner-egress-qualys"
  network = google_compute_network.scanner_network.name
  project = var.service_project_id

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  direction          = "EGRESS"
  destination_ranges = ["0.0.0.0/0"]
  target_tags        = ["qualys-scanner"]
}

resource "google_compute_firewall" "scanner_deny_ingress" {
  name    = "qualys-scanner-deny-ingress"
  network = google_compute_network.scanner_network.name
  project = var.service_project_id
  priority = 1000

  deny {
    protocol = "all"
  }

  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["qualys-scanner"]
}

# Scanner Instance Template
resource "google_compute_instance_template" "scanner" {
  for_each = toset(var.regions)

  name_prefix  = "qualys-scanner-${each.value}-"
  machine_type = var.scanner_machine_type
  project      = var.service_project_id
  region       = each.value

  tags = ["qualys-scanner"]
  labels = merge(var.labels, {
    role   = "scanner"
    region = each.value
  })

  disk {
    source_image = "projects/cos-cloud/global/images/family/cos-stable"
    auto_delete  = true
    boot         = true
    disk_size_gb = var.scanner_disk_size_gb
    disk_type    = "pd-balanced"
  }

  # Additional disk for mounting snapshots
  disk {
    auto_delete  = false
    boot         = false
    device_name  = "scanner-data"
    disk_size_gb = 100
    disk_type    = "pd-standard"
    mode         = "READ_WRITE"
    type         = "PERSISTENT"
  }

  network_interface {
    network    = google_compute_network.scanner_network.id
    subnetwork = google_compute_subnetwork.scanner_subnet[each.value].id

    # No external IP - use Cloud NAT
  }

  service_account {
    email  = var.scanner_service_account
    scopes = ["cloud-platform"]
  }

  scheduling {
    preemptible         = var.use_preemptible_scanners
    automatic_restart   = !var.use_preemptible_scanners
    on_host_maintenance = var.use_preemptible_scanners ? "TERMINATE" : "MIGRATE"
  }

  metadata = {
    enable-oslogin = "TRUE"
    user-data = templatefile("${path.module}/cloud-init.yaml", {
      qscanner_image     = var.qscanner_image != "" ? var.qscanner_image : "gcr.io/qualys-public/qscanner:latest"
      qualys_secret_name = var.qualys_secret_name
      project_id         = var.service_project_id
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Managed Instance Groups
resource "google_compute_region_instance_group_manager" "scanner_mig" {
  for_each = toset(var.regions)

  name               = "qualys-scanner-mig-${each.value}"
  base_instance_name = "qualys-scanner"
  region             = each.value
  project            = var.service_project_id

  version {
    instance_template = google_compute_instance_template.scanner[each.value].id
  }

  target_size = var.scanner_instances_per_region

  named_port {
    name = "http"
    port = 8080
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.scanner[each.value].id
    initial_delay_sec = 300
  }

  update_policy {
    type                         = "PROACTIVE"
    minimal_action               = "REPLACE"
    max_surge_fixed              = 3
    max_unavailable_fixed        = 0
    instance_redistribution_type = "PROACTIVE"
  }
}

# Health Check
resource "google_compute_health_check" "scanner" {
  for_each = toset(var.regions)

  name    = "qualys-scanner-health-${each.value}"
  project = var.service_project_id

  timeout_sec         = 5
  check_interval_sec  = 30
  healthy_threshold   = 2
  unhealthy_threshold = 3

  tcp_health_check {
    port = "22"
  }
}

# Autoscaler (optional - scale based on Pub/Sub queue depth)
resource "google_compute_region_autoscaler" "scanner" {
  for_each = toset(var.regions)

  name    = "qualys-scanner-autoscaler-${each.value}"
  region  = each.value
  project = var.service_project_id
  target  = google_compute_region_instance_group_manager.scanner_mig[each.value].id

  autoscaling_policy {
    max_replicas    = var.scanner_instances_per_region * 2
    min_replicas    = 1
    cooldown_period = 300

    cpu_utilization {
      target = 0.7
    }
  }
}

output "instance_template_self_links" {
  description = "Self links of instance templates"
  value       = { for k, v in google_compute_instance_template.scanner : k => v.self_link }
}

output "instance_group_urls" {
  description = "Instance group URLs"
  value       = { for k, v in google_compute_region_instance_group_manager.scanner_mig : k => v.instance_group }
}

output "network_id" {
  description = "Scanner network ID"
  value       = google_compute_network.scanner_network.id
}
