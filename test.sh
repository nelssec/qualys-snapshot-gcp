#!/bin/bash
# Test script for Qualys GCP Snapshot Scanner
# Validates configuration and infrastructure without deploying

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"
FUNCTIONS_DIR="$SCRIPT_DIR/cloud-functions"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

passed=0
failed=0
warnings=0

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((passed++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((failed++))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((warnings++))
}

log_info() {
    echo "[INFO] $1"
}

echo "=========================================="
echo "Qualys GCP Scanner - Validation Tests"
echo "=========================================="
echo ""

# Test 1: Check directory structure
log_info "Checking directory structure..."
required_dirs=(
    "terraform"
    "terraform/modules/iam"
    "terraform/modules/firestore"
    "terraform/modules/pubsub"
    "terraform/modules/scanner"
    "terraform/modules/workflows"
    "cloud-functions/discovery"
    "scanner/scripts"
    "docs"
)

for dir in "${required_dirs[@]}"; do
    if [ -d "$SCRIPT_DIR/$dir" ]; then
        log_pass "Directory exists: $dir"
    else
        log_fail "Missing directory: $dir"
    fi
done

# Test 2: Check required files
log_info "Checking required files..."
required_files=(
    "terraform/main.tf"
    "terraform/variables.tf"
    "terraform/terraform.tfvars.example"
    "cloud-functions/discovery/main.py"
    "cloud-functions/discovery/requirements.txt"
    "deploy.sh"
    "README.md"
    "ARCHITECTURE.md"
)

for file in "${required_files[@]}"; do
    if [ -f "$SCRIPT_DIR/$file" ]; then
        log_pass "File exists: $file"
    else
        log_fail "Missing file: $file"
    fi
done

# Test 3: Validate shell scripts syntax
log_info "Validating shell script syntax..."
while IFS= read -r -d '' script; do
    if bash -n "$script" 2>/dev/null; then
        log_pass "Shell syntax valid: ${script#$SCRIPT_DIR/}"
    else
        log_fail "Shell syntax error: ${script#$SCRIPT_DIR/}"
    fi
done < <(find "$SCRIPT_DIR" -name "*.sh" -type f -print0)

# Test 4: Validate Python syntax
log_info "Validating Python syntax..."
while IFS= read -r -d '' pyfile; do
    if python3 -m py_compile "$pyfile" 2>/dev/null; then
        log_pass "Python syntax valid: ${pyfile#$SCRIPT_DIR/}"
    else
        log_fail "Python syntax error: ${pyfile#$SCRIPT_DIR/}"
    fi
done < <(find "$FUNCTIONS_DIR" -name "*.py" -type f -print0 2>/dev/null || true)

# Test 5: Check Terraform file syntax (basic)
log_info "Checking Terraform file syntax..."
if command -v terraform >/dev/null 2>&1; then
    cd "$TERRAFORM_DIR"
    if terraform fmt -check -recursive >/dev/null 2>&1; then
        log_pass "Terraform formatting is correct"
    else
        log_warn "Terraform files need formatting (run: terraform fmt -recursive)"
    fi

    if terraform init -backend=false >/dev/null 2>&1; then
        if terraform validate >/dev/null 2>&1; then
            log_pass "Terraform validation passed"
        else
            log_fail "Terraform validation failed"
        fi
    else
        log_warn "Could not initialize Terraform (missing providers)"
    fi
    cd "$SCRIPT_DIR"
else
    log_warn "Terraform not installed - skipping validation"
fi

# Test 6: Check for configuration template
log_info "Checking configuration..."
if [ -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
    log_warn "terraform.tfvars exists (ensure credentials are not committed)"

    # Check for placeholder values
    if grep -q "my-service-project\|your-qualys" "$TERRAFORM_DIR/terraform.tfvars" 2>/dev/null; then
        log_fail "terraform.tfvars contains placeholder values"
    else
        log_pass "terraform.tfvars appears configured"
    fi
else
    log_info "terraform.tfvars not found (expected for initial setup)"
fi

# Test 7: Check for QScanner binary
log_info "Checking for QScanner binary..."
if [ -f "/opt/bin/qscanner" ]; then
    log_pass "QScanner binary found at /opt/bin/qscanner"
elif command -v qscanner >/dev/null 2>&1; then
    log_pass "QScanner found in PATH"
else
    log_warn "QScanner binary not found (required for actual scanning)"
fi

# Test 8: Check workflow YAML syntax
log_info "Checking Cloud Workflow syntax..."
workflow_files=$(find "$SCRIPT_DIR/terraform/modules/workflows" -name "*.yaml" -type f 2>/dev/null || true)
if [ -n "$workflow_files" ]; then
    for workflow in $workflow_files; do
        # Basic YAML syntax check
        if python3 -c "import yaml; yaml.safe_load(open('$workflow'))" 2>/dev/null; then
            log_pass "Workflow YAML valid: ${workflow#$SCRIPT_DIR/}"
        else
            log_fail "Workflow YAML error: ${workflow#$SCRIPT_DIR/}"
        fi
    done
else
    log_warn "No workflow YAML files found"
fi

# Test 9: Check documentation completeness
log_info "Checking documentation..."
docs=(
    "README.md"
    "ARCHITECTURE.md"
    "IMPLEMENTATION_STATUS.md"
    "docs/QSCANNER_SETUP.md"
)

for doc in "${docs[@]}"; do
    if [ -f "$SCRIPT_DIR/$doc" ]; then
        # Check if documentation has reasonable content (> 1KB)
        size=$(wc -c < "$SCRIPT_DIR/$doc")
        if [ "$size" -gt 1000 ]; then
            log_pass "Documentation complete: $doc"
        else
            log_warn "Documentation may be incomplete: $doc"
        fi
    else
        log_fail "Missing documentation: $doc"
    fi
done

# Test 10: Check for emojis in documentation (should be none)
log_info "Checking for emojis in documentation..."
emoji_count=$(find "$SCRIPT_DIR" -name "*.md" -type f -exec grep -o "[[:emoji:]]" {} \; 2>/dev/null | wc -l || echo 0)
if [ "$emoji_count" -eq 0 ]; then
    log_pass "No emojis found in documentation"
else
    log_warn "Found $emoji_count emoji characters in documentation"
fi

# Summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Passed:   $passed"
echo "Failed:   $failed"
echo "Warnings: $warnings"
echo ""

if [ "$failed" -eq 0 ]; then
    echo -e "${GREEN}All critical tests passed${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed - review errors above${NC}"
    exit 1
fi
