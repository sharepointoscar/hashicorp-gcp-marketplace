#!/usr/bin/env bash
# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Boundary Enterprise - Post-Deployment Test Script
#
# Architecture: Local orchestration + remote validation
#   Phase 1 (local):  Gather terraform outputs, discover controller VMs
#   Phase 2 (remote): SSH into controller, run all validation from inside GCP
#
# This ensures all checks work regardless of LB scheme (internal or external).
#
# Usage:
#   ./scripts/post-deploy-test.sh --project=PROJECT_ID [--region=REGION]
#
# Prerequisites:
#   - terraform apply completed successfully
#   - gcloud CLI authenticated with IAP tunnel access
#   - Run from directory containing terraform.tfstate
#------------------------------------------------------------------------------

set -euo pipefail

# Parse arguments
ARG_PROJECT_ID=""
ARG_REGION=""
INIT_AUTH_METHOD_ID=""
INIT_LOGIN_NAME=""
INIT_PASSWORD=""

for arg in "$@"; do
    case $arg in
        --project=*)
            ARG_PROJECT_ID="${arg#*=}"
            ;;
        --region=*)
            ARG_REGION="${arg#*=}"
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRODUCT_DIR="$(dirname "$SCRIPT_DIR")"

# Determine working directory: find where terraform.tfstate lives
if [[ -f "$PWD/terraform.tfstate" ]]; then
    WORK_DIR="$PWD"
elif [[ -f "$PRODUCT_DIR/terraform.tfstate" ]]; then
    WORK_DIR="$PRODUCT_DIR"
elif [[ -f "$PRODUCT_DIR/test/terraform.tfstate" ]]; then
    WORK_DIR="$PRODUCT_DIR/test"
else
    echo "ERROR: No terraform.tfstate found. Run 'terraform apply' first."
    echo "Searched: $PWD, $PRODUCT_DIR, $PRODUCT_DIR/test"
    exit 1
fi

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------
print_header() {
    echo -e "\n${BLUE}==========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}==========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "  $1"
}

ssh_to_controller() {
    local vm="$1"
    local zone="$2"
    local cmd="$3"
    gcloud compute ssh "$vm" \
        --project="$PROJECT_ID" \
        --zone="$zone" \
        --tunnel-through-iap \
        --command="$cmd" \
        -- -o ConnectTimeout=30 -o StrictHostKeyChecking=no 2>/dev/null
}

#==============================================================================
# PHASE 1: LOCAL — Gather terraform outputs, discover infrastructure
#==============================================================================

gather_outputs() {
    print_header "Phase 1: Gathering Terraform Outputs (local)"

    cd "$WORK_DIR"
    print_info "Working directory: $WORK_DIR"

    # Detect tfvars file
    if [[ -f "marketplace_test.tfvars" ]]; then
        TFVARS_FILE="marketplace_test.tfvars"
    elif [[ -f "terraform.tfvars" ]]; then
        TFVARS_FILE="terraform.tfvars"
    else
        TFVARS_FILE=""
    fi

    # Get outputs from terraform state
    BOUNDARY_FQDN=$(terraform output -raw boundary_url 2>/dev/null | sed 's|https://||' | sed 's|:.*||') || true
    LB_IP=$(terraform output -raw controller_load_balancer_ip 2>/dev/null) || true

    REGION="${ARG_REGION}"
    if [[ -z "$REGION" ]]; then
        REGION=$(terraform output -raw region 2>/dev/null) || true
    fi

    # Get project_id: CLI arg > terraform output > tfvars
    PROJECT_ID="${ARG_PROJECT_ID}"
    if [[ -z "$PROJECT_ID" ]]; then
        PROJECT_ID=$(terraform output -raw project_id 2>/dev/null) || true
    fi
    if [[ -z "$PROJECT_ID" ]] && [[ -n "$TFVARS_FILE" ]]; then
        PROJECT_ID=$(grep '^project_id' "$TFVARS_FILE" 2>/dev/null | sed 's/.*=.*"\(.*\)"/\1/' | tr -d ' ') || true
    fi
    if [[ -z "$PROJECT_ID" ]]; then
        print_error "Could not determine project_id. Use --project=PROJECT_ID"
        exit 1
    fi

    if [[ -z "$LB_IP" ]]; then
        print_error "Could not get load balancer IP from terraform outputs"
        exit 1
    fi

    # Get deployment prefix
    FRIENDLY_PREFIX=""
    if [[ -n "$TFVARS_FILE" ]]; then
        FRIENDLY_PREFIX=$(grep '^goog_cm_deployment_name' "$TFVARS_FILE" 2>/dev/null | sed 's/.*=.*"\(.*\)"/\1/' | tr -d ' ') || true
    fi
    if [[ -z "$FRIENDLY_PREFIX" ]]; then
        FRIENDLY_PREFIX=$(terraform output -raw friendly_name_prefix 2>/dev/null) || true
    fi
    if [[ -z "$FRIENDLY_PREFIX" ]] && [[ -n "$TFVARS_FILE" ]]; then
        FRIENDLY_PREFIX=$(grep '^friendly_name_prefix' "$TFVARS_FILE" 2>/dev/null | sed 's/.*=.*"\(.*\)"/\1/' | tr -d ' ') || true
    fi
    FRIENDLY_PREFIX="${FRIENDLY_PREFIX:-bnd}"

    # Discover ALL controller VMs
    CONTROLLER_VMS_RAW=$(gcloud compute instances list \
        --project="$PROJECT_ID" \
        --filter="name~${FRIENDLY_PREFIX}.*boundary.*controller OR name~${FRIENDLY_PREFIX}.*bnd.*ctl" \
        --format="csv[no-heading](name,zone)" 2>/dev/null) || true

    if [[ -z "$CONTROLLER_VMS_RAW" ]]; then
        CONTROLLER_VMS_RAW=$(gcloud compute instances list \
            --project="$PROJECT_ID" \
            --filter="name~boundary.*controller" \
            --format="csv[no-heading](name,zone)" 2>/dev/null) || true
    fi

    CONTROLLER_NAMES=()
    CONTROLLER_ZONES=()
    while IFS=',' read -r name zone; do
        [[ -n "$name" ]] && CONTROLLER_NAMES+=("$name") && CONTROLLER_ZONES+=("$zone")
    done <<< "$CONTROLLER_VMS_RAW"

    CONTROLLER_VM="${CONTROLLER_NAMES[0]:-}"
    CONTROLLER_ZONE="${CONTROLLER_ZONES[0]:-}"

    if [[ -z "$CONTROLLER_VM" ]]; then
        print_error "No controller VMs found"
        exit 1
    fi

    print_info "Boundary FQDN:     $BOUNDARY_FQDN"
    print_info "Load Balancer IP:  $LB_IP"
    print_info "Project ID:        $PROJECT_ID"
    print_info "Deployment Prefix: $FRIENDLY_PREFIX"
    print_info "Controller VMs:    ${CONTROLLER_NAMES[*]}"
    print_info "Primary Controller: $CONTROLLER_VM ($CONTROLLER_ZONE)"
    print_success "Terraform outputs gathered"
}

#==============================================================================
# PHASE 2: REMOTE — SSH into controller, validate everything from inside GCP
#==============================================================================

run_remote_validation() {
    print_header "Phase 2: Remote Validation (via SSH to $CONTROLLER_VM)"

    print_info "Uploading validation script to controller..."

    # Build the remote validation script as a heredoc.
    # All checks run from inside the controller where the network is reachable.
    REMOTE_SCRIPT=$(cat <<'REMOTE_EOF'
#!/usr/bin/env bash
set -uo pipefail

BOUNDARY_FQDN="__BOUNDARY_FQDN__"
LB_IP="__LB_IP__"
PROJECT_ID="__PROJECT_ID__"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

check_pass() { echo -e "${GREEN}✓ $1${NC}"; ((PASS_COUNT++)); }
check_fail() { echo -e "${RED}✗ $1${NC}"; ((FAIL_COUNT++)); }
check_warn() { echo -e "${YELLOW}⚠ $1${NC}"; ((WARN_COUNT++)); }
print_info() { echo -e "  $1"; }

echo ""
echo "=========================================="
echo "Remote Validation (running on $(hostname))"
echo "=========================================="

#--- Check 1: Boundary service ---
echo -e "\n${BLUE}[1/7] Boundary Service${NC}"
if systemctl is-active --quiet boundary 2>/dev/null; then
    VERSION=$(boundary version 2>/dev/null | head -1 || echo "unknown")
    check_pass "Boundary service is active ($VERSION)"
else
    check_fail "Boundary service is not running"
    print_info "$(sudo systemctl status boundary 2>&1 | head -5)"
fi

#--- Check 2: API health endpoint (port 9200) ---
echo -e "\n${BLUE}[2/7] API Endpoint (port 9200)${NC}"
API_RESPONSE=$(curl -sk -o /dev/null -w "%{http_code}" "https://127.0.0.1:9200" 2>/dev/null) || API_RESPONSE="000"
if [[ "$API_RESPONSE" == "200" ]]; then
    check_pass "API endpoint responding (HTTP $API_RESPONSE)"
else
    check_fail "API endpoint returned HTTP $API_RESPONSE"
fi

#--- Check 3: Cluster endpoint (port 9201) ---
echo -e "\n${BLUE}[3/7] Cluster Endpoint (port 9201)${NC}"
CLUSTER_RESPONSE=$(curl -sk -o /dev/null -w "%{http_code}" "https://127.0.0.1:9201" 2>/dev/null) || CLUSTER_RESPONSE="000"
if [[ "$CLUSTER_RESPONSE" != "000" ]]; then
    check_pass "Cluster endpoint responding (HTTP $CLUSTER_RESPONSE)"
else
    check_warn "Cluster endpoint not responding (may be normal if not yet peered)"
fi

#--- Check 4: Auth methods (database initialization) ---
echo -e "\n${BLUE}[4/7] Database Initialization${NC}"
AUTH_RESPONSE=$(curl -sk "https://127.0.0.1:9200/v1/auth-methods?scope_id=global" 2>/dev/null) || AUTH_RESPONSE=""
if echo "$AUTH_RESPONSE" | grep -q '"id"'; then
    AUTH_METHOD_ID=$(echo "$AUTH_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    check_pass "Database initialized — auth method: $AUTH_METHOD_ID"
else
    check_fail "No auth methods found — database may not be initialized"
fi

#--- Check 5: Load balancer reachability ---
echo -e "\n${BLUE}[5/7] Load Balancer ($LB_IP:9200)${NC}"
LB_RESPONSE=$(curl -sk -o /dev/null -w "%{http_code}" "https://$LB_IP:9200" 2>/dev/null) || LB_RESPONSE="000"
if [[ "$LB_RESPONSE" == "200" ]]; then
    check_pass "Load balancer responding (HTTP $LB_RESPONSE)"
else
    check_warn "Load balancer returned HTTP $LB_RESPONSE (may still be warming up)"
fi

#--- Check 6: Scopes API (functional test) ---
echo -e "\n${BLUE}[6/7] Scopes API (functional test)${NC}"
SCOPES_RESPONSE=$(curl -sk "https://127.0.0.1:9200/v1/scopes?scope_id=global" 2>/dev/null) || SCOPES_RESPONSE=""
if echo "$SCOPES_RESPONSE" | grep -q '"scope_id"'; then
    SCOPE_COUNT=$(echo "$SCOPES_RESPONSE" | grep -o '"scope_id"' | wc -l)
    check_pass "Scopes API working ($SCOPE_COUNT scope(s) found)"
else
    check_fail "Scopes API not returning expected data"
fi

#--- Check 7: Authentication test ---
echo -e "\n${BLUE}[7/7] Authentication Test${NC}"
INIT_LOGIN="__INIT_LOGIN_NAME__"
INIT_PASS="__INIT_PASSWORD__"
if [[ -n "$AUTH_METHOD_ID" ]] && [[ -n "$INIT_LOGIN" ]] && [[ "$INIT_LOGIN" != "" ]]; then
    AUTH_RESULT=$(curl -sk -X POST "https://127.0.0.1:9200/v1/auth-methods/${AUTH_METHOD_ID}:authenticate" \
        -d "{\"attributes\":{\"login_name\":\"$INIT_LOGIN\",\"password\":\"$INIT_PASS\"}}" 2>/dev/null) || AUTH_RESULT=""
    if echo "$AUTH_RESULT" | grep -q '"token"'; then
        check_pass "Authentication successful with admin credentials"
    else
        check_warn "Authentication attempt did not return a token"
    fi
elif [[ -n "$AUTH_METHOD_ID" ]]; then
    check_pass "Auth method exists ($AUTH_METHOD_ID) — credentials not available for login test"
else
    check_warn "No auth method found — skipping authentication test"
fi

#--- Summary ---
echo ""
echo "=========================================="
echo "Validation Results"
echo "=========================================="
echo -e "  ${GREEN}Passed: $PASS_COUNT${NC}"
[[ $WARN_COUNT -gt 0 ]] && echo -e "  ${YELLOW}Warnings: $WARN_COUNT${NC}"
[[ $FAIL_COUNT -gt 0 ]] && echo -e "  ${RED}Failed: $FAIL_COUNT${NC}"
echo ""

# Exit with failure if any checks failed
[[ $FAIL_COUNT -gt 0 ]] && exit 1
exit 0
REMOTE_EOF
)

    # Inject actual values into the remote script
    REMOTE_SCRIPT="${REMOTE_SCRIPT//__BOUNDARY_FQDN__/$BOUNDARY_FQDN}"
    REMOTE_SCRIPT="${REMOTE_SCRIPT//__LB_IP__/$LB_IP}"
    REMOTE_SCRIPT="${REMOTE_SCRIPT//__PROJECT_ID__/$PROJECT_ID}"
    REMOTE_SCRIPT="${REMOTE_SCRIPT//__INIT_LOGIN_NAME__/$INIT_LOGIN_NAME}"
    REMOTE_SCRIPT="${REMOTE_SCRIPT//__INIT_PASSWORD__/$INIT_PASSWORD}"

    # Execute remote validation via SSH
    REMOTE_EXIT=0
    gcloud compute ssh "$CONTROLLER_VM" \
        --project="$PROJECT_ID" \
        --zone="$CONTROLLER_ZONE" \
        --tunnel-through-iap \
        --command="$REMOTE_SCRIPT" \
        -- -o ConnectTimeout=30 -o StrictHostKeyChecking=no 2>/dev/null || REMOTE_EXIT=$?

    return $REMOTE_EXIT
}

#==============================================================================
# PHASE 3: LOCAL — Handle database init if needed, install CLI
#==============================================================================

handle_database_init() {
    print_header "Phase 3: Database Initialization Check"

    # Cloud-init runs a full `boundary database init` on every controller.
    # The first controller to acquire the DB lock creates auth methods, scopes,
    # targets, and logs the admin credentials. Secondary controllers get
    # "already initialized" and continue normally.

    # Verify auth methods exist via the API
    AUTH_CHECK=$(ssh_to_controller "$CONTROLLER_VM" "$CONTROLLER_ZONE" \
        "curl -sk 'https://127.0.0.1:9200/v1/auth-methods?scope_id=global' 2>/dev/null || echo ''") || true

    if echo "$AUTH_CHECK" | grep -q '"id"'; then
        INIT_AUTH_METHOD_ID=$(echo "$AUTH_CHECK" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        print_success "Auth methods exist — auth method: $INIT_AUTH_METHOD_ID"
    else
        print_error "No auth methods found — cloud-init may not have completed"
        print_info "Check cloud-init log: sudo cat /var/log/boundary-cloud-init.log"
        return 1
    fi

    # Retrieve admin credentials from cloud-init log
    # Try each controller — only the one that won the DB lock has credentials
    for i in "${!CONTROLLER_NAMES[@]}"; do
        local vm="${CONTROLLER_NAMES[$i]}"
        local zone="${CONTROLLER_ZONES[$i]}"
        CREDS_LOG=$(ssh_to_controller "$vm" "$zone" \
            "sudo cat /var/log/boundary-cloud-init.log 2>/dev/null | grep -A4 'BOUNDARY INITIAL ADMIN CREDENTIALS' || echo ''") || true

        if echo "$CREDS_LOG" | grep -q "Login Name:"; then
            INIT_LOGIN_NAME=$(echo "$CREDS_LOG" | grep "Login Name:" | awk '{print $NF}')
            INIT_PASSWORD=$(echo "$CREDS_LOG" | grep "Password:" | awk '{print $NF}')
            print_success "Admin credentials found on $vm"
            echo ""
            echo -e "${YELLOW}==========================================${NC}"
            echo -e "${YELLOW}BOUNDARY INITIAL ADMIN CREDENTIALS${NC}"
            echo -e "${YELLOW}==========================================${NC}"
            echo ""
            echo "  Auth Method ID: $INIT_AUTH_METHOD_ID"
            echo "  Login Name:     $INIT_LOGIN_NAME"
            echo "  Password:       $INIT_PASSWORD"
            echo ""
            echo -e "${YELLOW}==========================================${NC}"
            return 0
        fi
    done

    print_warning "Credentials not found in cloud-init logs (may have been rotated)"
}

install_cli() {
    print_header "Phase 4: Local Boundary CLI"

    if command -v boundary &> /dev/null; then
        BOUNDARY_VERSION=$(boundary version 2>/dev/null | head -1)
        print_success "Boundary CLI already installed: $BOUNDARY_VERSION"
        return 0
    fi

    print_info "Boundary CLI not found. Installing..."

    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) print_warning "Unsupported architecture: $ARCH — skipping CLI install"; return 0 ;;
    esac

    BOUNDARY_VERSION="0.21.0"
    DOWNLOAD_URL="https://releases.hashicorp.com/boundary/${BOUNDARY_VERSION}+ent/boundary_${BOUNDARY_VERSION}+ent_${OS}_${ARCH}.zip"

    TEMP_DIR=$(mktemp -d)
    if curl -sLo "$TEMP_DIR/boundary.zip" "$DOWNLOAD_URL" && \
       unzip -qo "$TEMP_DIR/boundary.zip" -d "$TEMP_DIR" 2>/dev/null; then

        if [[ -w /usr/local/bin ]]; then
            mv "$TEMP_DIR/boundary" /usr/local/bin/
        elif sudo -n mv "$TEMP_DIR/boundary" /usr/local/bin/ 2>/dev/null; then
            true
        else
            mkdir -p "$HOME/.local/bin"
            mv "$TEMP_DIR/boundary" "$HOME/.local/bin/"
            export PATH="$HOME/.local/bin:$PATH"
        fi
        print_success "Boundary CLI installed"
    else
        print_warning "Failed to download/install Boundary CLI"
        print_info "Install manually: https://developer.hashicorp.com/boundary/install"
    fi
    rm -rf "$TEMP_DIR"
}

#==============================================================================
# SUMMARY
#==============================================================================

print_summary() {
    print_header "Post-Deployment Summary"

    echo ""
    echo "Deployment:"
    echo "  Boundary URL:     https://$BOUNDARY_FQDN:9200"
    echo "  Load Balancer IP: $LB_IP"
    echo "  Project:          $PROJECT_ID"
    echo "  Controllers:      ${#CONTROLLER_NAMES[@]}"
    echo ""
    echo "Quick Commands:"
    echo "  # SSH to controller"
    echo "  gcloud compute ssh $CONTROLLER_VM --zone=$CONTROLLER_ZONE --tunnel-through-iap"
    echo ""
    echo "  # View controller logs"
    echo "  gcloud compute ssh $CONTROLLER_VM --zone=$CONTROLLER_ZONE --tunnel-through-iap \\"
    echo "    -- sudo journalctl -u boundary -f"
    echo ""
    echo "  # Retrieve initial admin credentials"
    echo "  gcloud compute ssh $CONTROLLER_VM --zone=$CONTROLLER_ZONE --tunnel-through-iap \\"
    echo "    -- sudo cat /var/log/boundary-cloud-init.log | grep -A7 'BOUNDARY INITIAL ADMIN CREDENTIALS'"
    echo ""
}

#==============================================================================
# MAIN
#==============================================================================

main() {
    echo "=========================================="
    echo "Boundary Enterprise Post-Deployment Test"
    echo "=========================================="

    # Phase 1: Local — gather terraform outputs
    gather_outputs

    # Phase 3: Database init if needed (must happen before remote validation)
    handle_database_init

    # Phase 2: Remote — run all validation from inside the controller
    REMOTE_EXIT=0
    run_remote_validation || REMOTE_EXIT=$?

    # Phase 4: Local — install CLI
    install_cli

    # Summary
    print_summary

    if [[ $REMOTE_EXIT -eq 0 ]]; then
        echo ""
        print_success "Post-deployment testing complete!"
    else
        echo ""
        print_error "Some remote validation checks failed (exit code: $REMOTE_EXIT)"
        exit 1
    fi
}

main "$@"
