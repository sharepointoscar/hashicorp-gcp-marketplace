#!/bin/bash
# shared/scripts/lib/common.sh
# Common shell functions for all HashiCorp GCP Marketplace products

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Print functions
print_step() {
    echo -e "\n${YELLOW}=== Step $1: $2 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

# Docker build with marketplace-compliant flags
docker_build_mp() {
    local image_tag="$1"
    local dockerfile="$2"
    local context="$3"
    local service_name="${4:-}"

    local annotation_flag=""
    if [ -n "$service_name" ]; then
        annotation_flag="--annotation com.googleapis.cloudmarketplace.product.service.name=$service_name"
    fi

    docker buildx build \
        --platform linux/amd64 \
        --provenance=false \
        --sbom=false \
        $annotation_flag \
        --tag "$image_tag" \
        -f "$dockerfile" \
        --push \
        "$context"
}

# Load product configuration from product.yaml
load_product_config() {
    local product_dir="$1"
    local config_file="$product_dir/product.yaml"

    if [ ! -f "$config_file" ]; then
        print_error "Product config not found: $config_file"
        return 1
    fi

    # Parse YAML using grep/sed (portable)
    export PRODUCT_ID=$(grep "^  id:" "$config_file" | head -1 | awk '{print $2}')
    export PRODUCT_VERSION=$(grep "^  version:" "$config_file" | head -1 | awk '{print $2}' | tr -d '"')
    export PARTNER_ID=$(grep "^  partnerId:" "$config_file" | head -1 | awk '{print $2}')
    export SOLUTION_ID=$(grep "^  solutionId:" "$config_file" | head -1 | awk '{print $2}')

    print_success "Loaded config for $PRODUCT_ID v$PRODUCT_VERSION"
}

# Verify prerequisites are installed
check_prerequisites() {
    local missing=()

    command -v docker &>/dev/null || missing+=("docker")
    command -v gcloud &>/dev/null || missing+=("gcloud")
    command -v kubectl &>/dev/null || missing+=("kubectl")

    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing prerequisites: ${missing[*]}"
        return 1
    fi

    print_success "All prerequisites installed"
    return 0
}

# Check if mpdev is available
check_mpdev() {
    if command -v mpdev &>/dev/null || [ -f "$HOME/bin/mpdev" ]; then
        print_success "mpdev is available"
        return 0
    fi

    print_warning "mpdev not found, creating wrapper..."
    mkdir -p "$HOME/bin"
    cat > "$HOME/bin/mpdev" << 'MPDEV_EOF'
#!/bin/bash
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v ~/.kube:/root/.kube \
  -v ~/.config/gcloud:/root/.config/gcloud \
  -v "$(pwd)":/app \
  -w /app \
  gcr.io/cloud-marketplace-tools/k8s/dev "$@"
MPDEV_EOF
    chmod +x "$HOME/bin/mpdev"
    export PATH="$HOME/bin:$PATH"
    print_success "mpdev wrapper created at $HOME/bin/mpdev"
}
