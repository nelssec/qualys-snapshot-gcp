#!/bin/bash
# Qualys GCP Snapshot Scanner - Deployment Script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"
FUNCTIONS_DIR="${SCRIPT_DIR}/cloud-functions"

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI not found. Please install: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi

    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform not found. Please install: https://www.terraform.io/downloads"
        exit 1
    fi

    # Check if authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "Not authenticated with gcloud. Run: gcloud auth login"
        exit 1
    fi

    log_info "Prerequisites check passed"
}

enable_apis() {
    local project_id="$1"
    log_info "Enabling required APIs in project: ${project_id}"

    local apis=(
        "compute.googleapis.com"
        "cloudfunctions.googleapis.com"
        "workflows.googleapis.com"
        "pubsub.googleapis.com"
        "firestore.googleapis.com"
        "cloudscheduler.googleapis.com"
        "eventarc.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "secretmanager.googleapis.com"
        "artifactregistry.googleapis.com"
        "iam.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )

    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        gcloud services enable "${api}" --project="${project_id}" || log_warn "Failed to enable ${api}"
    done

    log_info "APIs enabled successfully"
}

create_terraform_backend() {
    local project_id="$1"
    local bucket_name="${project_id}-qualys-terraform-state"

    log_info "Creating Terraform state bucket: ${bucket_name}"

    # Check if bucket exists
    if gsutil ls -b "gs://${bucket_name}" &> /dev/null; then
        log_warn "Bucket already exists: ${bucket_name}"
    else
        gsutil mb -p "${project_id}" -l us-central1 "gs://${bucket_name}"
        gsutil versioning set on "gs://${bucket_name}"
        log_info "Terraform state bucket created"
    fi

    # Update backend configuration
    cat > "${TERRAFORM_DIR}/backend.tf" <<EOF
terraform {
  backend "gcs" {
    bucket = "${bucket_name}"
    prefix = "qualys-snapshot-scanner"
  }
}
EOF

    log_info "Backend configuration created"
}

validate_tfvars() {
    log_info "Validating terraform.tfvars..."

    if [ ! -f "${TERRAFORM_DIR}/terraform.tfvars" ]; then
        log_error "terraform.tfvars not found. Copy terraform.tfvars.example and configure it."
        exit 1
    fi

    # Check for placeholder values
    if grep -q "my-service-project-id\|your-qualys-username\|your-qualys-password" "${TERRAFORM_DIR}/terraform.tfvars"; then
        log_error "terraform.tfvars contains placeholder values. Please update with real values."
        exit 1
    fi

    log_info "terraform.tfvars validation passed"
}

deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."

    cd "${TERRAFORM_DIR}"

    # Initialize Terraform
    log_info "Running terraform init..."
    terraform init

    # Validate configuration
    log_info "Running terraform validate..."
    terraform validate

    # Plan deployment
    log_info "Running terraform plan..."
    terraform plan -out=tfplan

    # Ask for confirmation
    echo ""
    read -p "Do you want to apply this plan? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_warn "Deployment cancelled"
        exit 0
    fi

    # Apply
    log_info "Running terraform apply..."
    terraform apply tfplan

    log_info "Infrastructure deployed successfully"
}

deploy_cloud_functions() {
    log_info "Deploying Cloud Functions..."

    # Get service project ID from terraform output
    cd "${TERRAFORM_DIR}"
    local project_id
    project_id=$(terraform output -raw service_project_id || echo "")

    if [ -z "$project_id" ]; then
        log_error "Could not get service project ID from Terraform output"
        exit 1
    fi

    # Deploy discovery function
    log_info "Deploying discovery function..."
    cd "${FUNCTIONS_DIR}/discovery"

    gcloud functions deploy qualys-discovery \
        --gen2 \
        --runtime=python311 \
        --region=us-central1 \
        --source=. \
        --entry-point=main \
        --trigger-topic=qualys-discovery \
        --project="${project_id}" \
        --service-account="qualys-function-sa@${project_id}.iam.gserviceaccount.com" \
        --set-env-vars="SERVICE_PROJECT_ID=${project_id}"

    log_info "Cloud Functions deployed successfully"
}

setup_monitoring() {
    local project_id="$1"

    log_info "Setting up monitoring and alerting..."

    # Create log-based metrics
    gcloud logging metrics create qualys-scan-failures \
        --project="${project_id}" \
        --description="Count of failed Qualys scans" \
        --log-filter='resource.type="cloud_workflows" AND severity>=ERROR' \
        --value-extractor='' \
        || log_warn "Metric already exists or failed to create"

    log_info "Monitoring setup complete"
}

show_summary() {
    log_info "Deployment Summary"
    echo ""
    echo "=========================================="
    echo "  Qualys GCP Snapshot Scanner Deployed"
    echo "=========================================="
    echo ""

    cd "${TERRAFORM_DIR}"

    echo "Service Account Emails:"
    terraform output scanner_service_account_email || true
    terraform output function_service_account_email || true
    terraform output workflow_service_account_email || true
    echo ""

    echo "Pub/Sub Topics:"
    terraform output discovery_topic_id || true
    echo ""

    echo "Cloud Workflows:"
    terraform output scan_workflow_id || true
    echo ""

    echo "Next Steps:"
    echo "1. Verify scanner instances are running in each region"
    echo "2. Check Cloud Scheduler jobs are enabled"
    echo "3. Monitor first scan execution in Cloud Workflows"
    echo "4. Review logs in Cloud Logging"
    echo ""
    echo "Useful Commands:"
    echo "  - View workflow executions: gcloud workflows executions list --workflow=qualys-main-orchestration"
    echo "  - View logs: gcloud logging read 'resource.type=\"cloud_workflows\"' --limit=50"
    echo "  - Trigger discovery: gcloud pubsub topics publish qualys-discovery --message='{\"type\":\"manual\"}'"
    echo ""
}

# Main
main() {
    log_info "Starting Qualys GCP Snapshot Scanner deployment..."
    echo ""

    check_prerequisites

    # Get service project ID
    if [ ! -f "${TERRAFORM_DIR}/terraform.tfvars" ]; then
        log_error "terraform.tfvars not found. Run: cp terraform/terraform.tfvars.example terraform/terraform.tfvars"
        exit 1
    fi

    local service_project_id
    service_project_id=$(grep 'service_project_id' "${TERRAFORM_DIR}/terraform.tfvars" | cut -d'"' -f2)

    if [ -z "$service_project_id" ] || [ "$service_project_id" = "my-service-project-id" ]; then
        log_error "Please configure service_project_id in terraform.tfvars"
        exit 1
    fi

    # Set gcloud project
    gcloud config set project "${service_project_id}"

    # Enable APIs
    enable_apis "${service_project_id}"

    # Create Terraform backend
    create_terraform_backend "${service_project_id}"

    # Validate configuration
    validate_tfvars

    # Deploy infrastructure
    deploy_infrastructure

    # Deploy Cloud Functions
    deploy_cloud_functions

    # Setup monitoring
    setup_monitoring "${service_project_id}"

    # Show summary
    show_summary

    log_info "Deployment completed successfully!"
}

# Run main if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
