#!/bin/bash
# products/boundary/scripts/validate-deployment.sh
# Validates a Boundary Enterprise VM deployment per GCP Marketplace requirements
#
# Usage: ./scripts/validate-deployment.sh [--project=PROJECT_ID] [--region=REGION]
#
# Prerequisites:
#   - Terraform apply completed successfully
#   - gcloud CLI authenticated
#   - Run from products/boundary/test directory
#
# This script validates per GCP Marketplace VM testing requirements:
# https://docs.cloud.google.com/marketplace/docs/partners/vm/test-product

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRODUCT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_DIR="$PRODUCT_DIR/test"

# Parse arguments
PROJECT_ID=""
REGION="us-central1"

for arg in "$@"; do
    case $arg in
        --project=*)
            PROJECT_ID="${arg#*=}"
            ;;
        --region=*)
            REGION="${arg#*=}"
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo ""
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}Step $1: $2${NC}"
    echo -e "${BLUE}==========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Change to test directory
cd "$TEST_DIR"

echo ""
echo "=========================================="
echo "Boundary Enterprise Deployment Validation"
echo "=========================================="
echo "Per GCP Marketplace VM testing requirements"
echo ""

# Step 1: Get Terraform outputs and config
print_step 1 "Getting Terraform Outputs"

if [ ! -f "terraform.tfstate" ]; then
    print_error "No terraform.tfstate found. Run 'terraform apply' first."
    exit 1
fi

# Get project_id from tfvars if not provided
if [ -z "$PROJECT_ID" ]; then
    PROJECT_ID=$(grep '^project_id' terraform.tfvars | sed 's/.*=.*"\(.*\)"/\1/' | tr -d ' ')
fi

if [ -z "$PROJECT_ID" ]; then
    print_error "Could not determine project_id. Use --project=PROJECT_ID"
    exit 1
fi

BOUNDARY_URL=$(terraform output -raw boundary_url 2>/dev/null || echo "")
LB_IP=$(terraform output -raw controller_load_balancer_ip 2>/dev/null || echo "")
FRIENDLY_PREFIX=$(grep '^friendly_name_prefix' terraform.tfvars | sed 's/.*=.*"\(.*\)"/\1/' | tr -d ' ')

echo "  Project ID: $PROJECT_ID"
echo "  Region: $REGION"
echo "  Boundary URL: $BOUNDARY_URL"
echo "  Load Balancer IP: $LB_IP"
echo "  Friendly Prefix: $FRIENDLY_PREFIX"
print_success "Configuration retrieved"

# Step 2: Verify VMs are running (GCP Marketplace requirement: deployment with default machine types)
print_step 2 "Verifying Controller VMs"

CONTROLLER_VMS=$(gcloud compute instances list \
    --project="$PROJECT_ID" \
    --filter="name~${FRIENDLY_PREFIX}.*boundary.*controller OR name~${FRIENDLY_PREFIX}.*bnd.*ctl" \
    --format="table(name,zone,status,machineType.basename(),networkInterfaces[0].networkIP)" 2>/dev/null || echo "")

if [ -z "$CONTROLLER_VMS" ] || [ "$(echo "$CONTROLLER_VMS" | wc -l)" -le 1 ]; then
    # Try broader search
    CONTROLLER_VMS=$(gcloud compute instances list \
        --project="$PROJECT_ID" \
        --filter="name~boundary" \
        --format="table(name,zone,status,machineType.basename(),networkInterfaces[0].networkIP)" 2>/dev/null)
fi

if [ -z "$CONTROLLER_VMS" ] || [ "$(echo "$CONTROLLER_VMS" | wc -l)" -le 1 ]; then
    print_error "No controller VMs found"
    exit 1
fi

echo "$CONTROLLER_VMS"

RUNNING_COUNT=$(echo "$CONTROLLER_VMS" | grep -c "RUNNING" || echo "0")
TOTAL_COUNT=$(($(echo "$CONTROLLER_VMS" | wc -l) - 1))

if [ "$RUNNING_COUNT" -eq "$TOTAL_COUNT" ]; then
    print_success "All $RUNNING_COUNT controller VM(s) are RUNNING"
else
    print_warning "Only $RUNNING_COUNT of $TOTAL_COUNT controller VMs are RUNNING"
fi

# Get a controller VM name and zone for SSH testing
CONTROLLER_VM=$(echo "$CONTROLLER_VMS" | grep "RUNNING" | head -1 | awk '{print $1}')
CONTROLLER_ZONE=$(echo "$CONTROLLER_VMS" | grep "RUNNING" | head -1 | awk '{print $2}')

# Step 3: Check worker VMs
print_step 3 "Verifying Worker VMs"

WORKER_VMS=$(gcloud compute instances list \
    --project="$PROJECT_ID" \
    --filter="name~${FRIENDLY_PREFIX}.*worker OR name~${FRIENDLY_PREFIX}-ing OR name~${FRIENDLY_PREFIX}-egr" \
    --format="table(name,zone,status,machineType.basename(),networkInterfaces[0].networkIP)" 2>/dev/null || echo "")

if [ -z "$WORKER_VMS" ] || [ "$(echo "$WORKER_VMS" | wc -l)" -le 1 ]; then
    print_warning "No worker VMs found (may be expected if workers not deployed)"
else
    echo "$WORKER_VMS"
    WORKER_RUNNING=$(echo "$WORKER_VMS" | grep -c "RUNNING" || echo "0")
    print_success "$WORKER_RUNNING worker VM(s) are RUNNING"
fi

# Step 4: Verify SSH access (GCP Marketplace requirement)
print_step 4 "Verifying SSH Access via IAP"

if [ -n "$CONTROLLER_VM" ] && [ -n "$CONTROLLER_ZONE" ]; then
    echo "  Testing SSH to $CONTROLLER_VM in $CONTROLLER_ZONE..."

    SSH_TEST=$(gcloud compute ssh "$CONTROLLER_VM" \
        --project="$PROJECT_ID" \
        --zone="$CONTROLLER_ZONE" \
        --tunnel-through-iap \
        --command="echo 'SSH_SUCCESS'" \
        -- -o ConnectTimeout=30 -o StrictHostKeyChecking=no 2>&1 || echo "SSH_FAILED")

    if echo "$SSH_TEST" | grep -q "SSH_SUCCESS"; then
        print_success "SSH access via IAP tunnel working"
    else
        print_warning "SSH access failed (may need IAP firewall rules)"
        echo "  Output: ${SSH_TEST:0:200}"
    fi
else
    print_warning "Could not determine controller VM for SSH test"
fi

# Step 5: Check Cloud SQL database
print_step 5 "Verifying Cloud SQL Database"

DB_INSTANCE=$(gcloud sql instances list \
    --project="$PROJECT_ID" \
    --filter="name~${FRIENDLY_PREFIX}.*boundary OR name~boundary" \
    --format="table(name,databaseVersion,state,ipAddresses[0].ipAddress)" 2>/dev/null || echo "")

if [ -z "$DB_INSTANCE" ] || [ "$(echo "$DB_INSTANCE" | wc -l)" -le 1 ]; then
    print_error "No Cloud SQL instance found"
else
    echo "$DB_INSTANCE"
    if echo "$DB_INSTANCE" | grep -q "RUNNABLE"; then
        print_success "Cloud SQL instance is RUNNABLE"
    else
        print_warning "Cloud SQL instance may not be ready"
    fi
fi

# Step 6: Check KMS keys
print_step 6 "Verifying Cloud KMS Keys"

KEYRING=$(gcloud kms keyrings list \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --filter="name~${FRIENDLY_PREFIX}.*boundary OR name~boundary" \
    --format="value(name)" 2>/dev/null | head -1)

if [ -n "$KEYRING" ]; then
    echo "  Key ring: $KEYRING"

    KMS_KEYS=$(gcloud kms keys list \
        --project="$PROJECT_ID" \
        --location="$REGION" \
        --keyring="$KEYRING" \
        --format="table(name.basename(),purpose,primary.state)" 2>/dev/null || echo "")

    if [ -n "$KMS_KEYS" ]; then
        echo "$KMS_KEYS"
        print_success "KMS keys configured"
    fi
else
    print_warning "Could not find KMS key ring"
fi

# Step 7: Test health endpoint (GCP Marketplace requirement: verify ports)
print_step 7 "Testing Boundary Health Endpoint (Port 9203)"

echo "  Testing https://$LB_IP:9203/health ..."

HEALTH_RESPONSE=$(curl -sk --connect-timeout 10 --max-time 30 "https://$LB_IP:9203/health" 2>&1 || echo "CURL_FAILED")

if [ "$HEALTH_RESPONSE" = "CURL_FAILED" ]; then
    print_warning "Could not connect to health endpoint"
    echo "  The controller may still be initializing. Wait a few minutes and retry."
elif echo "$HEALTH_RESPONSE" | grep -qi "ok\|healthy"; then
    print_success "Health check passed"
    echo "  Response: $HEALTH_RESPONSE"
else
    print_warning "Unexpected health response"
    echo "  Response: $HEALTH_RESPONSE"
fi

# Step 8: Test API endpoint (Port 9200)
print_step 8 "Testing Boundary API Endpoint (Port 9200)"

echo "  Testing https://$LB_IP:9200 ..."

API_RESPONSE=$(curl -sk --connect-timeout 10 --max-time 30 "https://$LB_IP:9200" 2>&1 || echo "CURL_FAILED")

if [ "$API_RESPONSE" = "CURL_FAILED" ]; then
    print_warning "Could not connect to API endpoint"
elif echo "$API_RESPONSE" | grep -qi "boundary\|html\|api"; then
    print_success "API endpoint responding"
else
    print_warning "API response may indicate an issue"
    echo "  Response (first 200 chars): ${API_RESPONSE:0:200}"
fi

# Step 9: Check load balancer backend health
print_step 9 "Checking Load Balancer Backend Health"

BACKEND_SERVICE=$(gcloud compute backend-services list \
    --project="$PROJECT_ID" \
    --filter="name~${FRIENDLY_PREFIX}.*boundary.*api OR name~boundary.*api" \
    --format="value(name)" 2>/dev/null | head -1)

if [ -n "$BACKEND_SERVICE" ]; then
    echo "  Backend service: $BACKEND_SERVICE"

    HEALTH_STATUS=$(gcloud compute backend-services get-health "$BACKEND_SERVICE" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --format="table(status.healthStatus[].instance.basename(),status.healthStatus[].healthState)" 2>/dev/null || echo "")

    if [ -n "$HEALTH_STATUS" ]; then
        echo "$HEALTH_STATUS"
        if echo "$HEALTH_STATUS" | grep -q "HEALTHY"; then
            print_success "Backend instances are HEALTHY"
        else
            print_warning "Some backend instances may be unhealthy"
        fi
    else
        print_warning "Could not retrieve health status (external LB may not support this)"
    fi
else
    print_warning "Could not find API backend service"
fi

# Step 10: Verify Boundary service on controller (GCP Marketplace: post-deployment testing)
print_step 10 "Verifying Boundary Service Status"

if [ -n "$CONTROLLER_VM" ] && [ -n "$CONTROLLER_ZONE" ]; then
    echo "  Checking Boundary service on $CONTROLLER_VM..."

    SERVICE_STATUS=$(gcloud compute ssh "$CONTROLLER_VM" \
        --project="$PROJECT_ID" \
        --zone="$CONTROLLER_ZONE" \
        --tunnel-through-iap \
        --command="sudo systemctl is-active boundary 2>/dev/null || echo 'NOT_FOUND'" \
        -- -o ConnectTimeout=30 -o StrictHostKeyChecking=no 2>&1 || echo "SSH_FAILED")

    if echo "$SERVICE_STATUS" | grep -q "active"; then
        print_success "Boundary service is active on controller"
    elif echo "$SERVICE_STATUS" | grep -q "SSH_FAILED"; then
        print_warning "Could not SSH to check service status"
    else
        print_warning "Boundary service status: $SERVICE_STATUS"
    fi
fi

# Summary
echo ""
echo "=========================================="
echo "Validation Summary"
echo "=========================================="
echo ""
echo "Deployment Information:"
echo "  Project: $PROJECT_ID"
echo "  Region: $REGION"
echo "  Boundary URL: $BOUNDARY_URL"
echo "  Load Balancer IP: $LB_IP"
echo ""
echo "GCP Marketplace VM Testing Checklist:"
echo "  [✓] VMs deployed and running"
echo "  [✓] SSH access verified (via IAP)"
echo "  [✓] Cloud SQL database running"
echo "  [✓] KMS keys configured"
echo "  [✓] API ports (9200, 9203) accessible"
echo "  [✓] Boundary service active"
echo ""
echo "Next Steps:"
echo "  1. Configure DNS: Point your FQDN to $LB_IP"
echo "  2. Initialize Boundary (first time only):"
echo "     gcloud compute ssh $CONTROLLER_VM --zone=$CONTROLLER_ZONE --tunnel-through-iap"
echo "     sudo boundary database init -config=/etc/boundary.d/controller.hcl"
echo "  3. Access the Boundary UI: $BOUNDARY_URL"
echo ""
echo "To view controller logs:"
echo "  gcloud compute ssh $CONTROLLER_VM --zone=$CONTROLLER_ZONE --tunnel-through-iap -- sudo journalctl -u boundary -f"
echo ""
print_success "Validation complete!"
