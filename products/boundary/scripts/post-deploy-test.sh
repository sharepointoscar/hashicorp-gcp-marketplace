#!/usr/bin/env bash
# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Boundary Enterprise - Post-Deployment Test Script
#
# This script performs end-to-end testing after terraform apply:
# 1. Configures /etc/hosts for local DNS resolution
# 2. Initializes Boundary database (first deployment)
# 3. Verifies UI accessibility
# 4. Installs Boundary CLI (if not present)
# 5. Authenticates to Boundary
#------------------------------------------------------------------------------

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR/../test"

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

#------------------------------------------------------------------------------
# Get Terraform Outputs
#------------------------------------------------------------------------------
get_terraform_outputs() {
    print_header "Step 1: Getting Terraform Outputs"

    if [[ ! -d "$TEST_DIR" ]]; then
        print_error "Test directory not found: $TEST_DIR"
        exit 1
    fi

    cd "$TEST_DIR"

    # Get outputs
    BOUNDARY_FQDN=$(terraform output -raw boundary_url 2>/dev/null | sed 's|https://||' | sed 's|:.*||') || true
    LB_IP=$(terraform output -raw controller_load_balancer_ip 2>/dev/null) || true
    PROJECT_ID=$(terraform output -raw project_id 2>/dev/null) || true
    REGION=$(terraform output -raw region 2>/dev/null) || true

    if [[ -z "$LB_IP" ]]; then
        print_error "Could not get load balancer IP from terraform outputs"
        exit 1
    fi

    # Get controller VM name and zone
    FRIENDLY_PREFIX=$(terraform output -raw friendly_name_prefix 2>/dev/null) || FRIENDLY_PREFIX="bnd"
    CONTROLLER_VM=$(gcloud compute instances list \
        --project="$PROJECT_ID" \
        --filter="name~${FRIENDLY_PREFIX}-boundary-controller" \
        --format="value(name)" \
        --limit=1 2>/dev/null) || true
    CONTROLLER_ZONE=$(gcloud compute instances list \
        --project="$PROJECT_ID" \
        --filter="name~${FRIENDLY_PREFIX}-boundary-controller" \
        --format="value(zone)" \
        --limit=1 2>/dev/null) || true

    print_info "Boundary FQDN: $BOUNDARY_FQDN"
    print_info "Load Balancer IP: $LB_IP"
    print_info "Project ID: $PROJECT_ID"
    print_info "Controller VM: $CONTROLLER_VM"
    print_info "Controller Zone: $CONTROLLER_ZONE"
    print_success "Configuration retrieved"
}

#------------------------------------------------------------------------------
# Step 1: Configure DNS (/etc/hosts)
#------------------------------------------------------------------------------
configure_dns() {
    print_header "Step 2: Configuring Local DNS (/etc/hosts)"

    # Check if entry already exists
    if grep -q "$BOUNDARY_FQDN" /etc/hosts 2>/dev/null; then
        EXISTING_IP=$(grep "$BOUNDARY_FQDN" /etc/hosts | awk '{print $1}' | head -1)
        if [[ "$EXISTING_IP" == "$LB_IP" ]]; then
            print_success "DNS entry already configured: $LB_IP $BOUNDARY_FQDN"
            return 0
        else
            print_warning "Existing entry found with different IP: $EXISTING_IP"
            print_info "Updating to: $LB_IP $BOUNDARY_FQDN"
            # Remove old entry and add new one
            sudo sed -i.bak "/$BOUNDARY_FQDN/d" /etc/hosts
        fi
    fi

    # Add new entry
    print_info "Adding DNS entry: $LB_IP $BOUNDARY_FQDN"
    echo "$LB_IP $BOUNDARY_FQDN" | sudo tee -a /etc/hosts > /dev/null

    # Verify
    if grep -q "$LB_IP.*$BOUNDARY_FQDN" /etc/hosts; then
        print_success "DNS entry added to /etc/hosts"
    else
        print_error "Failed to add DNS entry"
        exit 1
    fi
}

#------------------------------------------------------------------------------
# Step 2: Initialize Boundary Database
#------------------------------------------------------------------------------
initialize_database() {
    print_header "Step 3: Checking/Initializing Boundary Database"

    if [[ -z "$CONTROLLER_VM" ]] || [[ -z "$CONTROLLER_ZONE" ]]; then
        print_error "Could not determine controller VM details"
        exit 1
    fi

    # First, check if auth methods exist (indicates proper initialization)
    print_info "Checking if Boundary has auth methods configured..."

    AUTH_CHECK=$(curl -sk "https://$LB_IP:9200/v1/auth-methods?scope_id=global" 2>/dev/null) || true

    if echo "$AUTH_CHECK" | grep -q '"id"'; then
        # Auth methods exist - database is properly initialized
        AUTH_METHOD_ID=$(echo "$AUTH_CHECK" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        print_success "Boundary database properly initialized"
        print_info "Auth Method ID: $AUTH_METHOD_ID"

        # Retrieve credentials from cloud-init logs
        print_info "Retrieving initial credentials from cloud-init logs..."
        CREDS_OUTPUT=$(gcloud compute ssh "$CONTROLLER_VM" \
            --project="$PROJECT_ID" \
            --zone="$CONTROLLER_ZONE" \
            --tunnel-through-iap \
            -- "sudo cat /var/log/boundary-cloud-init.log | grep -A7 'BOUNDARY INITIAL ADMIN CREDENTIALS'" 2>/dev/null) || true

        if echo "$CREDS_OUTPUT" | grep -q "Password:"; then
            LOGIN_NAME=$(echo "$CREDS_OUTPUT" | grep "Login Name:" | awk '{print $NF}')
            PASSWORD=$(echo "$CREDS_OUTPUT" | grep "Password:" | awk '{print $NF}')

            echo ""
            echo -e "${YELLOW}==========================================${NC}"
            echo -e "${YELLOW}BOUNDARY INITIAL ADMIN CREDENTIALS${NC}"
            echo -e "${YELLOW}==========================================${NC}"
            echo ""
            echo "  Auth Method ID: $AUTH_METHOD_ID"
            echo "  Login Name:     $LOGIN_NAME"
            echo "  Password:       $PASSWORD"
            echo ""
            echo -e "${YELLOW}==========================================${NC}"

            # Save to file
            CREDS_FILE="$TEST_DIR/boundary-init-creds.txt"
            cat > "$CREDS_FILE" <<EOF
# Boundary Initial Credentials
# Retrieved: $(date)
# WARNING: Store these securely and delete this file after saving elsewhere!

Auth Method ID: $AUTH_METHOD_ID
Login Name: $LOGIN_NAME
Password: $PASSWORD

Boundary URL: https://$BOUNDARY_FQDN:9200
EOF
            chmod 600 "$CREDS_FILE"
            print_warning "Credentials saved to: $CREDS_FILE"
            print_warning "DELETE this file after saving credentials securely!"
        else
            print_warning "Could not retrieve password from cloud-init logs"
            print_info "Logs may have been rotated or cleared"
            print_info "To manually retrieve, run:"
            print_info "  gcloud compute ssh $CONTROLLER_VM --zone=$CONTROLLER_ZONE --tunnel-through-iap \\"
            print_info "    -- sudo cat /var/log/boundary-cloud-init.log | grep -A5 \"BOUNDARY INITIAL ADMIN CREDENTIALS\""
        fi
        return 0
    fi

    # No auth methods - need to initialize properly
    print_warning "No auth methods found. Database needs initialization."
    print_info "Stopping Boundary service to initialize database..."

    # Stop service, init database, capture output, restart service
    INIT_OUTPUT=$(gcloud compute ssh "$CONTROLLER_VM" \
        --project="$PROJECT_ID" \
        --zone="$CONTROLLER_ZONE" \
        --tunnel-through-iap \
        --command="
            sudo systemctl stop boundary
            sleep 3
            sudo boundary database init -config=/etc/boundary.d/controller.hcl 2>&1
            INIT_EXIT=\$?
            sudo systemctl start boundary
            exit \$INIT_EXIT
        " 2>/dev/null) || true

    # Check if initialization succeeded
    if echo "$INIT_OUTPUT" | grep -q "Initial auth information"; then
        print_success "Boundary database initialized successfully!"

        # Extract credentials
        AUTH_METHOD_ID=$(echo "$INIT_OUTPUT" | grep "Auth Method ID:" | head -1 | awk '{print $NF}')
        LOGIN_NAME=$(echo "$INIT_OUTPUT" | grep "Login Name:" | head -1 | awk '{print $NF}')
        PASSWORD=$(echo "$INIT_OUTPUT" | grep "Password:" | head -1 | awk '{print $NF}')

        echo ""
        echo -e "${YELLOW}==========================================${NC}"
        echo -e "${YELLOW}IMPORTANT: Save these credentials!${NC}"
        echo -e "${YELLOW}==========================================${NC}"
        echo ""
        echo "  Auth Method ID: $AUTH_METHOD_ID"
        echo "  Login Name:     $LOGIN_NAME"
        echo "  Password:       $PASSWORD"
        echo ""
        echo -e "${YELLOW}==========================================${NC}"

        # Save to file
        CREDS_FILE="$TEST_DIR/boundary-init-creds.txt"
        cat > "$CREDS_FILE" <<EOF
# Boundary Initial Credentials
# Generated: $(date)
# WARNING: Store these securely and delete this file after saving elsewhere!

Auth Method ID: $AUTH_METHOD_ID
Login Name: $LOGIN_NAME
Password: $PASSWORD

Boundary URL: https://$BOUNDARY_FQDN:9200
EOF
        chmod 600 "$CREDS_FILE"
        print_warning "Credentials saved to: $CREDS_FILE"
        print_warning "DELETE this file after saving credentials securely!"

        # Wait for service to be ready
        print_info "Waiting for Boundary service to be ready..."
        sleep 10

        return 0

    elif echo "$INIT_OUTPUT" | grep -q "already been initialized"; then
        # Schema initialized but no auth methods - this is the problematic state
        print_warning "Database schema exists but no auth methods were created."
        print_info "This can happen if cloud-init was interrupted."
        print_info "Attempting to recreate with fresh database..."

        # We need to drop and recreate the database
        REINIT_OUTPUT=$(gcloud compute ssh "$CONTROLLER_VM" \
            --project="$PROJECT_ID" \
            --zone="$CONTROLLER_ZONE" \
            --tunnel-through-iap \
            --command="
                sudo systemctl stop boundary
                sleep 2

                # Get database connection info from config
                DB_URL=\$(sudo grep -A5 'database {' /etc/boundary.d/controller.hcl | grep 'url' | sed 's/.*\"\\(.*\\)\".*/\\1/')

                # Extract components (user:pass@host/dbname)
                DB_HOST=\$(echo \"\$DB_URL\" | sed 's|.*@\\([^/]*\\)/.*|\\1|')
                DB_NAME=\$(echo \"\$DB_URL\" | sed 's|.*/\\([^?]*\\).*|\\1|')
                DB_USER=\$(echo \"\$DB_URL\" | sed 's|.*://\\([^:]*\\):.*|\\1|')
                DB_PASS=\$(echo \"\$DB_URL\" | sed 's|.*://[^:]*:\\([^@]*\\)@.*|\\1|')

                # Install psql if not present
                which psql > /dev/null 2>&1 || sudo apt-get install -y postgresql-client > /dev/null 2>&1

                # Drop and recreate database
                PGPASSWORD=\"\$DB_PASS\" psql -h \"\$DB_HOST\" -U \"\$DB_USER\" -d postgres -c \"DROP DATABASE IF EXISTS \$DB_NAME;\" 2>&1
                PGPASSWORD=\"\$DB_PASS\" psql -h \"\$DB_HOST\" -U \"\$DB_USER\" -d postgres -c \"CREATE DATABASE \$DB_NAME;\" 2>&1

                # Now initialize
                sudo boundary database init -config=/etc/boundary.d/controller.hcl 2>&1
                INIT_EXIT=\$?

                sudo systemctl start boundary
                exit \$INIT_EXIT
            " 2>/dev/null) || true

        if echo "$REINIT_OUTPUT" | grep -q "Initial auth information"; then
            print_success "Boundary database reinitialized successfully!"

            # Extract credentials
            AUTH_METHOD_ID=$(echo "$REINIT_OUTPUT" | grep "Auth Method ID:" | head -1 | awk '{print $NF}')
            LOGIN_NAME=$(echo "$REINIT_OUTPUT" | grep "Login Name:" | head -1 | awk '{print $NF}')
            PASSWORD=$(echo "$REINIT_OUTPUT" | grep "Password:" | head -1 | awk '{print $NF}')

            echo ""
            echo -e "${YELLOW}==========================================${NC}"
            echo -e "${YELLOW}IMPORTANT: Save these credentials!${NC}"
            echo -e "${YELLOW}==========================================${NC}"
            echo ""
            echo "  Auth Method ID: $AUTH_METHOD_ID"
            echo "  Login Name:     $LOGIN_NAME"
            echo "  Password:       $PASSWORD"
            echo ""
            echo -e "${YELLOW}==========================================${NC}"

            # Save to file
            CREDS_FILE="$TEST_DIR/boundary-init-creds.txt"
            cat > "$CREDS_FILE" <<EOF
# Boundary Initial Credentials
# Generated: $(date)
# WARNING: Store these securely and delete this file after saving elsewhere!

Auth Method ID: $AUTH_METHOD_ID
Login Name: $LOGIN_NAME
Password: $PASSWORD

Boundary URL: https://$BOUNDARY_FQDN:9200
EOF
            chmod 600 "$CREDS_FILE"
            print_warning "Credentials saved to: $CREDS_FILE"
            print_warning "DELETE this file after saving credentials securely!"

            sleep 10
            return 0
        else
            print_error "Failed to reinitialize database"
            echo "$REINIT_OUTPUT" | tail -20
            return 1
        fi
    else
        print_error "Database initialization failed"
        echo "$INIT_OUTPUT" | tail -30
        return 1
    fi
}

#------------------------------------------------------------------------------
# Step 3: Verify UI Accessibility
#------------------------------------------------------------------------------
verify_ui() {
    print_header "Step 4: Verifying Boundary UI Accessibility"

    BOUNDARY_URL="https://$BOUNDARY_FQDN:9200"
    print_info "Testing: $BOUNDARY_URL"

    # Test with curl
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "$BOUNDARY_URL" 2>/dev/null) || HTTP_CODE="000"

    if [[ "$HTTP_CODE" == "200" ]]; then
        print_success "Boundary UI is accessible (HTTP $HTTP_CODE)"
        print_info "Open in browser: $BOUNDARY_URL"
    else
        print_error "Could not access Boundary UI (HTTP $HTTP_CODE)"
        print_info "Checking direct IP access..."
        HTTP_CODE_IP=$(curl -sk -o /dev/null -w "%{http_code}" "https://$LB_IP:9200" 2>/dev/null) || HTTP_CODE_IP="000"
        if [[ "$HTTP_CODE_IP" == "200" ]]; then
            print_warning "Direct IP access works. DNS may need time to propagate."
        fi
        return 1
    fi
}

#------------------------------------------------------------------------------
# Step 4: Install Boundary CLI
#------------------------------------------------------------------------------
install_cli() {
    print_header "Step 5: Installing Boundary CLI"

    # Check if already installed
    if command -v boundary &> /dev/null; then
        BOUNDARY_VERSION=$(boundary version 2>/dev/null | head -1)
        print_success "Boundary CLI already installed: $BOUNDARY_VERSION"
        return 0
    fi

    print_info "Boundary CLI not found. Installing..."

    # Detect OS
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)

    case "$ARCH" in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) print_error "Unsupported architecture: $ARCH"; return 1 ;;
    esac

    # Get latest version
    BOUNDARY_VERSION="0.21.0"
    DOWNLOAD_URL="https://releases.hashicorp.com/boundary/${BOUNDARY_VERSION}+ent/boundary_${BOUNDARY_VERSION}+ent_${OS}_${ARCH}.zip"

    print_info "Downloading from: $DOWNLOAD_URL"

    # Create temp directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    # Download and extract
    if ! curl -sLO "$DOWNLOAD_URL"; then
        print_error "Failed to download Boundary CLI"
        cd - > /dev/null
        rm -rf "$TEMP_DIR"
        return 1
    fi

    if ! unzip -q "boundary_${BOUNDARY_VERSION}+ent_${OS}_${ARCH}.zip" 2>/dev/null; then
        print_error "Failed to extract Boundary CLI"
        cd - > /dev/null
        rm -rf "$TEMP_DIR"
        return 1
    fi

    # Install - try without sudo first, then with sudo
    INSTALL_SUCCESS=false
    if [[ -w /usr/local/bin ]]; then
        mv boundary /usr/local/bin/ && INSTALL_SUCCESS=true
    else
        # Try sudo, but don't fail the whole script if it doesn't work
        if sudo -n mv boundary /usr/local/bin/ 2>/dev/null; then
            INSTALL_SUCCESS=true
        else
            print_warning "Cannot install to /usr/local/bin (requires sudo)"
            print_info "Installing to ~/.local/bin instead..."
            mkdir -p "$HOME/.local/bin"
            mv boundary "$HOME/.local/bin/"
            if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
                print_warning "Add ~/.local/bin to your PATH:"
                print_info "  export PATH=\"\$HOME/.local/bin:\$PATH\""
            fi
            INSTALL_SUCCESS=true
        fi
    fi

    # Cleanup
    cd - > /dev/null
    rm -rf "$TEMP_DIR"

    # Verify
    if command -v boundary &> /dev/null; then
        INSTALLED_VERSION=$(boundary version 2>/dev/null | head -1)
        print_success "Boundary CLI installed: $INSTALLED_VERSION"
    elif [[ -x "$HOME/.local/bin/boundary" ]]; then
        INSTALLED_VERSION=$("$HOME/.local/bin/boundary" version 2>/dev/null | head -1)
        print_success "Boundary CLI installed to ~/.local/bin: $INSTALLED_VERSION"
        # Update PATH for this session
        export PATH="$HOME/.local/bin:$PATH"
    else
        print_warning "Boundary CLI installation location not in PATH"
        print_info "Install manually from: https://developer.hashicorp.com/boundary/install"
        return 0  # Don't fail the script
    fi
}

#------------------------------------------------------------------------------
# Step 5: Authenticate to Boundary
#------------------------------------------------------------------------------
authenticate() {
    print_header "Step 6: Authenticating to Boundary"

    export BOUNDARY_ADDR="https://$BOUNDARY_FQDN:9200"
    print_info "BOUNDARY_ADDR=$BOUNDARY_ADDR"

    # Check for saved credentials
    CREDS_FILE="$TEST_DIR/boundary-init-creds.txt"
    if [[ -f "$CREDS_FILE" ]]; then
        AUTH_METHOD_ID=$(grep "Auth Method ID:" "$CREDS_FILE" | awk '{print $NF}')
        LOGIN_NAME=$(grep "Login Name:" "$CREDS_FILE" | awk '{print $NF}')
        PASSWORD=$(grep "^Password:" "$CREDS_FILE" | awk '{print $NF}')

        if [[ -n "$AUTH_METHOD_ID" ]] && [[ -n "$LOGIN_NAME" ]] && [[ -n "$PASSWORD" ]]; then
            print_info "Using saved credentials from: $CREDS_FILE"
            print_info "Login Name: $LOGIN_NAME"
            print_info "Auth Method ID: $AUTH_METHOD_ID"

            # Authenticate using environment variable
            export BOUNDARY_PASSWORD="$PASSWORD"
            if boundary authenticate password \
                -addr="$BOUNDARY_ADDR" \
                -auth-method-id="$AUTH_METHOD_ID" \
                -login-name="$LOGIN_NAME" \
                -password="env://BOUNDARY_PASSWORD" \
                -tls-insecure 2>/dev/null; then
                print_success "Authentication successful!"
                unset BOUNDARY_PASSWORD

                # Test connection
                print_info "Testing API connection..."
                if boundary scopes list -tls-insecure 2>/dev/null; then
                    print_success "API connection verified"
                fi
                return 0
            else
                print_warning "Automated authentication failed"
                unset BOUNDARY_PASSWORD
            fi
        elif [[ -n "$AUTH_METHOD_ID" ]]; then
            # We have auth method but no password - show instructions
            print_info "Auth Method ID found: $AUTH_METHOD_ID"
            print_info "Password not saved (database was already initialized)"
        fi
    fi

    # Get auth method ID from API if not in file
    if [[ -z "$AUTH_METHOD_ID" ]]; then
        AUTH_METHOD_ID=$(curl -sk "https://$LB_IP:9200/v1/auth-methods?scope_id=global" 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4) || true
    fi

    # Manual authentication instructions
    print_warning "Manual authentication required"
    echo ""
    echo "To authenticate, run:"
    echo ""
    echo "  export BOUNDARY_ADDR=\"https://$BOUNDARY_FQDN:9200\""
    if [[ -n "$AUTH_METHOD_ID" ]]; then
        echo "  boundary authenticate password \\"
        echo "    -auth-method-id=\"$AUTH_METHOD_ID\" \\"
        echo "    -login-name=\"admin\" \\"
        echo "    -tls-insecure"
    else
        echo "  boundary authenticate"
    fi
    echo ""
    echo "Default credentials (if not changed):"
    echo "  Login Name: admin"
    echo "  Password: <from initial deployment output>"
    echo ""

    # Don't fail the script for manual auth
    return 0
}

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
print_summary() {
    print_header "Post-Deployment Test Summary"

    echo ""
    echo "Deployment Information:"
    echo "  Boundary URL: https://$BOUNDARY_FQDN:9200"
    echo "  Load Balancer IP: $LB_IP"
    echo "  Controller VM: $CONTROLLER_VM"
    echo ""
    echo "Quick Commands:"
    echo "  # Set environment"
    echo "  export BOUNDARY_ADDR=\"https://$BOUNDARY_FQDN:9200\""
    echo ""
    echo "  # Authenticate"
    echo "  boundary authenticate"
    echo ""
    echo "  # List scopes"
    echo "  boundary scopes list -tls-insecure"
    echo ""
    echo "  # View controller logs"
    echo "  gcloud compute ssh $CONTROLLER_VM --zone=$CONTROLLER_ZONE --tunnel-through-iap -- sudo journalctl -u boundary -f"
    echo ""
    echo "  # Retrieve initial admin credentials from cloud-init logs"
    echo "  gcloud compute ssh $CONTROLLER_VM --zone=$CONTROLLER_ZONE --tunnel-through-iap \\"
    echo "    -- sudo cat /var/log/boundary-cloud-init.log | grep -A5 \"BOUNDARY INITIAL ADMIN CREDENTIALS\""
    echo ""

    if [[ -f "$TEST_DIR/boundary-init-creds.txt" ]]; then
        echo -e "${YELLOW}WARNING: Initial credentials saved to: $TEST_DIR/boundary-init-creds.txt${NC}"
        echo -e "${YELLOW}         Delete this file after saving credentials securely!${NC}"
    fi
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------
main() {
    echo "=========================================="
    echo "Boundary Enterprise Post-Deployment Test"
    echo "=========================================="

    get_terraform_outputs
    configure_dns
    initialize_database
    verify_ui
    install_cli
    authenticate
    print_summary

    echo ""
    print_success "Post-deployment testing complete!"
}

# Run main
main "$@"
