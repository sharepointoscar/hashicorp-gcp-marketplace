#!/usr/bin/env bash
# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

#------------------------------------------------------------------------------
# Boundary Enterprise - Full Deployment with Comprehensive Logging
#
# This script orchestrates a complete Boundary deployment using existing
# Makefile targets and scripts, capturing all output to timestamped log files.
#
# Usage: ./deploy-with-logging.sh [OPTIONS]
#
# Options:
#   --destroy-existing    Destroy current deployment first
#   --skip-validation    Skip validation phase
#   --skip-post-test     Skip post-deployment tests
#   --dry-run            Run validation only
#   --logs-dir PATH      Custom log directory path
#   --help               Show help
#------------------------------------------------------------------------------

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DEFAULT_LOGS_DIR="$SCRIPT_DIR/logs/deployment-$TIMESTAMP"
LOGS_DIR="${LOGS_DIR:-$DEFAULT_LOGS_DIR}"

# Options (defaults)
DESTROY_EXISTING=false
SKIP_VALIDATION=false
SKIP_POST_TEST=false
DRY_RUN=false
CLEAN_LOGS=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------
print_header() {
    echo ""
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo ""
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
    echo -e "${CYAN}$1${NC}"
}

print_phase() {
    echo ""
    echo -e "${BLUE}=========================================="
    echo -e "Phase $1: $2"
    echo -e "==========================================${NC}"
    echo ""
}

print_step() {
    echo -e "${CYAN}[$1] $2${NC}"
}

# Strip ANSI color codes from a file
strip_colors() {
    local input_file="$1"
    local output_file="${input_file%.log}-clean.log"

    if [[ -f "$input_file" ]]; then
        sed 's/\x1b\[[0-9;]*m//g' "$input_file" > "$output_file"
        print_info "Clean log created: $(basename "$output_file")"
    fi
}

#------------------------------------------------------------------------------
# Usage/Help
#------------------------------------------------------------------------------
usage() {
    cat <<EOF
Boundary Enterprise - Full Deployment with Comprehensive Logging

Usage: ./deploy-with-logging.sh [OPTIONS]

Options:
  --destroy-existing    Destroy current deployment first
  --skip-validation     Skip validation phase
  --skip-post-test      Skip post-deployment tests
  --dry-run             Run validation only
  --clean-logs          Delete all log directories, then exit
  --logs-dir PATH       Custom log directory path
  --help                Show this help

Examples:
  # Full deployment with all phases
  ./deploy-with-logging.sh

  # Destroy existing deployment first, then deploy
  ./deploy-with-logging.sh --destroy-existing

  # Run validation only
  ./deploy-with-logging.sh --dry-run

  # Deploy with custom log directory
  ./deploy-with-logging.sh --logs-dir=/tmp/boundary-logs

  # Clean up all log directories
  ./deploy-with-logging.sh --clean-logs

Log Structure:
  logs/deployment-YYYYMMDD-HHMMSS/
  ├── 01-validate.log                    # Terraform + CFT validation
  ├── 01-validate-clean.log              # Same, without ANSI color codes
  ├── 02-terraform-apply.log             # Full deployment
  ├── 02-terraform-apply-clean.log       # Same, without ANSI color codes
  ├── 03-infrastructure-validation.log   # Infrastructure checks
  ├── 04-post-deploy-test.log            # Application testing
  ├── 05-controller-logs.log             # VM serial console logs
  ├── 06-worker-logs.log                 # Worker VM logs
  ├── terraform-outputs.json             # Terraform outputs
  ├── deployment-summary.json            # Deployment summary
  └── full-deployment.log                # Combined log
  └── full-deployment-clean.log          # Combined log without colors

Note: *-clean.log files have ANSI color codes stripped for easier reading in text editors.

EOF
}

#------------------------------------------------------------------------------
# Parse Arguments
#------------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --destroy-existing)
                DESTROY_EXISTING=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --skip-post-test)
                SKIP_POST_TEST=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --clean-logs)
                CLEAN_LOGS=true
                shift
                ;;
            --logs-dir)
                LOGS_DIR="$2"
                shift 2
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

#------------------------------------------------------------------------------
# Clean Logs
#------------------------------------------------------------------------------
clean_logs() {
    print_header "Cleaning Log Directories"

    local logs_base_dir="$SCRIPT_DIR/logs"

    if [[ ! -d "$logs_base_dir" ]]; then
        print_info "No logs directory found at: $logs_base_dir"
        return 0
    fi

    # Count deployment directories
    local deployment_dirs
    deployment_dirs=$(find "$logs_base_dir" -maxdepth 1 -type d -name "deployment-*" 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$deployment_dirs" -eq 0 ]]; then
        print_info "No deployment log directories found"
        return 0
    fi

    print_info "Found $deployment_dirs deployment log director(ies)"
    echo ""

    # List directories to be deleted
    print_step "CLEAN" "Directories to be deleted:"
    find "$logs_base_dir" -maxdepth 1 -type d -name "deployment-*" -exec basename {} \; | sort

    echo ""
    read -p "Delete all deployment log directories? (yes/no): " -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        print_warning "Cleanup cancelled by user"
        return 0
    fi

    # Delete deployment directories
    find "$logs_base_dir" -maxdepth 1 -type d -name "deployment-*" -exec rm -rf {} \;
    print_success "Deleted $deployment_dirs deployment log director(ies)"

    # Check if logs directory is now empty
    if [[ -z "$(ls -A "$logs_base_dir" 2>/dev/null)" ]]; then
        rmdir "$logs_base_dir"
        print_info "Removed empty logs directory"
    fi

    return 0
}

#------------------------------------------------------------------------------
# Setup Log Directory
#------------------------------------------------------------------------------
setup_logs() {
    print_step "SETUP" "Creating log directory: $LOGS_DIR"

    if [[ -d "$LOGS_DIR" ]]; then
        print_warning "Log directory already exists"
    else
        mkdir -p "$LOGS_DIR"
        print_success "Log directory created"
    fi

    # Create deployment start marker
    cat > "$LOGS_DIR/deployment-info.txt" <<EOF
Boundary Enterprise Deployment
Started: $(date)
Timestamp: $TIMESTAMP
Logs Directory: $LOGS_DIR

Options:
  Destroy Existing: $DESTROY_EXISTING
  Skip Validation: $SKIP_VALIDATION
  Skip Post Test: $SKIP_POST_TEST
  Dry Run: $DRY_RUN

Environment:
  Working Directory: $SCRIPT_DIR
  User: $(whoami)
  Hostname: $(hostname)
EOF

    print_info "Deployment info saved to: $LOGS_DIR/deployment-info.txt"
}

#------------------------------------------------------------------------------
# Print Configuration Summary
#------------------------------------------------------------------------------
print_config() {
    print_header "Deployment Configuration"

    echo "Timestamp: $TIMESTAMP"
    echo "Logs Directory: $LOGS_DIR"
    echo ""
    echo "Phases to Execute:"
    if [[ "$SKIP_VALIDATION" == "false" ]]; then
        echo "  ✓ Phase 1: Validation"
    else
        echo "  ✗ Phase 1: Validation (SKIPPED)"
    fi

    if [[ "$DESTROY_EXISTING" == "true" ]]; then
        echo "  ✓ Phase 2: Cleanup (destroy existing deployment)"
    else
        echo "  ✗ Phase 2: Cleanup (SKIPPED)"
    fi

    if [[ "$DRY_RUN" == "false" ]]; then
        echo "  ✓ Phase 3: Deployment (terraform apply)"
        echo "  ✓ Phase 4: Infrastructure Validation"
        if [[ "$SKIP_POST_TEST" == "false" ]]; then
            echo "  ✓ Phase 5: Post-Deployment Testing"
        else
            echo "  ✗ Phase 5: Post-Deployment Testing (SKIPPED)"
        fi
        echo "  ✓ Phase 6: Log Collection"
        echo "  ✓ Phase 7: Summary Generation"
    else
        echo "  ✗ Phase 3-7: SKIPPED (DRY RUN MODE)"
    fi

    echo ""
}

#------------------------------------------------------------------------------
# Phase 1: Validation
#------------------------------------------------------------------------------
run_validation() {
    if [[ "$SKIP_VALIDATION" == "true" ]]; then
        print_warning "Skipping validation phase"
        return 0
    fi

    print_phase 1 "Validation"

    local log_file="$LOGS_DIR/01-validate.log"
    local start_time=$(date +%s)

    print_step "VALIDATE" "Running: make validate/full"
    print_info "Log file: $log_file"

    # Run make validate/full and capture output
    if make validate/full 2>&1 | tee "$log_file"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        print_success "Validation passed (${duration}s)"
        echo "$duration" > "$LOGS_DIR/.phase1-duration"
        return 0
    else
        local exit_code=$?
        print_error "Validation failed (exit code: $exit_code)"
        echo "$exit_code" > "$LOGS_DIR/.phase1-exit-code"
        return $exit_code
    fi
}

#------------------------------------------------------------------------------
# Phase 2: Optional Cleanup
#------------------------------------------------------------------------------
run_cleanup() {
    if [[ "$DESTROY_EXISTING" == "false" ]]; then
        print_info "Skipping cleanup phase (no --destroy-existing flag)"
        return 0
    fi

    print_phase 2 "Cleanup (Destroying Existing Deployment)"

    local log_file="$LOGS_DIR/02a-terraform-destroy.log"
    local start_time=$(date +%s)

    print_warning "Destroying existing deployment"
    print_step "CLEANUP" "Running: make terraform/destroy"
    print_info "Log file: $log_file"

    # Run make terraform/destroy and capture output
    if make terraform/destroy 2>&1 | tee "$log_file"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        print_success "Cleanup completed (${duration}s)"
        echo "$duration" > "$LOGS_DIR/.phase2-duration"
        return 0
    else
        local exit_code=$?
        print_error "Cleanup failed (exit code: $exit_code)"
        echo "$exit_code" > "$LOGS_DIR/.phase2-exit-code"
        return $exit_code
    fi
}

#------------------------------------------------------------------------------
# Phase 3: Deployment
#------------------------------------------------------------------------------
run_deployment() {
    print_phase 3 "Deployment"

    local log_file="$LOGS_DIR/02-terraform-apply.log"
    local start_time=$(date +%s)

    print_step "DEPLOY" "Running: make terraform/apply"
    print_info "Log file: $log_file"
    print_warning "This phase typically takes 20-40 minutes"

    # Run make terraform/apply and capture output
    if make terraform/apply 2>&1 | tee "$log_file"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local duration_min=$((duration / 60))
        local duration_sec=$((duration % 60))
        print_success "Deployment completed (${duration_min}m ${duration_sec}s)"
        echo "$duration" > "$LOGS_DIR/.phase3-duration"
        return 0
    else
        local exit_code=$?
        print_error "Deployment failed (exit code: $exit_code)"
        echo "$exit_code" > "$LOGS_DIR/.phase3-exit-code"
        return $exit_code
    fi
}

#------------------------------------------------------------------------------
# Phase 4: Infrastructure Validation
#------------------------------------------------------------------------------
run_infrastructure_validation() {
    print_phase 4 "Infrastructure Validation"

    local log_file="$LOGS_DIR/03-infrastructure-validation.log"
    local start_time=$(date +%s)

    print_step "VALIDATE" "Running: scripts/validate-deployment.sh"
    print_info "Log file: $log_file"

    # Change to test directory for validation script
    if [[ -d "test" ]]; then
        cd test
    fi

    # Run validation script and capture output
    if "$SCRIPT_DIR/scripts/validate-deployment.sh" 2>&1 | tee "$log_file"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        print_success "Infrastructure validation passed (${duration}s)"
        echo "$duration" > "$LOGS_DIR/.phase4-duration"
        cd "$SCRIPT_DIR"
        return 0
    else
        local exit_code=$?
        print_error "Infrastructure validation failed (exit code: $exit_code)"
        echo "$exit_code" > "$LOGS_DIR/.phase4-exit-code"
        cd "$SCRIPT_DIR"
        return $exit_code
    fi
}

#------------------------------------------------------------------------------
# Phase 5: Post-Deployment Testing
#------------------------------------------------------------------------------
run_post_deploy_test() {
    if [[ "$SKIP_POST_TEST" == "true" ]]; then
        print_warning "Skipping post-deployment testing phase"
        return 0
    fi

    print_phase 5 "Post-Deployment Testing"

    local log_file="$LOGS_DIR/04-post-deploy-test.log"
    local start_time=$(date +%s)

    print_step "TEST" "Running: scripts/post-deploy-test.sh"
    print_info "Log file: $log_file"

    # Run post-deploy test and capture output
    if "$SCRIPT_DIR/scripts/post-deploy-test.sh" 2>&1 | tee "$log_file"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        print_success "Post-deployment testing completed (${duration}s)"
        echo "$duration" > "$LOGS_DIR/.phase5-duration"

        # Check if credentials file was created
        if [[ -f "test/boundary-init-creds.txt" ]]; then
            cp test/boundary-init-creds.txt "$LOGS_DIR/boundary-credentials.txt"
            print_warning "Initial credentials saved to: $LOGS_DIR/boundary-credentials.txt"
        fi

        return 0
    else
        local exit_code=$?
        print_error "Post-deployment testing failed (exit code: $exit_code)"
        echo "$exit_code" > "$LOGS_DIR/.phase5-exit-code"
        return $exit_code
    fi
}

#------------------------------------------------------------------------------
# Phase 6: Log Collection
#------------------------------------------------------------------------------
collect_logs() {
    print_phase 6 "Log Collection"

    local start_time=$(date +%s)

    # Get project ID and other info from terraform outputs
    cd test 2>/dev/null || cd "$SCRIPT_DIR"

    print_step "COLLECT" "Retrieving Terraform outputs"
    if terraform output -json > "$LOGS_DIR/terraform-outputs.json" 2>&1; then
        print_success "Terraform outputs saved"
    else
        print_warning "Could not retrieve terraform outputs"
    fi

    # Extract key information
    PROJECT_ID=$(terraform output -raw project_id 2>/dev/null || echo "")
    FRIENDLY_PREFIX=$(terraform output -raw friendly_name_prefix 2>/dev/null || echo "bnd")

    if [[ -n "$PROJECT_ID" ]]; then
        print_step "COLLECT" "Retrieving VM serial console logs"

        # Get controller logs
        CONTROLLER_VMS=$(gcloud compute instances list \
            --project="$PROJECT_ID" \
            --filter="name~${FRIENDLY_PREFIX}.*controller" \
            --format="value(name,zone)" 2>/dev/null || echo "")

        if [[ -n "$CONTROLLER_VMS" ]]; then
            echo "=== Controller VM Serial Console Logs ===" > "$LOGS_DIR/05-controller-logs.log"
            while IFS=$'\t' read -r vm_name vm_zone; do
                echo "" >> "$LOGS_DIR/05-controller-logs.log"
                echo "--- $vm_name ($vm_zone) ---" >> "$LOGS_DIR/05-controller-logs.log"
                gcloud compute instances get-serial-port-output "$vm_name" \
                    --project="$PROJECT_ID" \
                    --zone="$vm_zone" \
                    >> "$LOGS_DIR/05-controller-logs.log" 2>&1 || true
            done <<< "$CONTROLLER_VMS"
            print_success "Controller logs collected"
        fi

        # Get worker logs
        WORKER_VMS=$(gcloud compute instances list \
            --project="$PROJECT_ID" \
            --filter="name~${FRIENDLY_PREFIX}.*worker OR name~${FRIENDLY_PREFIX}-ing OR name~${FRIENDLY_PREFIX}-egr" \
            --format="value(name,zone)" 2>/dev/null || echo "")

        if [[ -n "$WORKER_VMS" ]]; then
            echo "=== Worker VM Serial Console Logs ===" > "$LOGS_DIR/06-worker-logs.log"
            while IFS=$'\t' read -r vm_name vm_zone; do
                echo "" >> "$LOGS_DIR/06-worker-logs.log"
                echo "--- $vm_name ($vm_zone) ---" >> "$LOGS_DIR/06-worker-logs.log"
                gcloud compute instances get-serial-port-output "$vm_name" \
                    --project="$PROJECT_ID" \
                    --zone="$vm_zone" \
                    >> "$LOGS_DIR/06-worker-logs.log" 2>&1 || true
            done <<< "$WORKER_VMS"
            print_success "Worker logs collected"
        fi
    else
        print_warning "Could not determine project ID for log collection"
    fi

    cd "$SCRIPT_DIR"

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    echo "$duration" > "$LOGS_DIR/.phase6-duration"
    print_success "Log collection completed (${duration}s)"
}

#------------------------------------------------------------------------------
# Phase 7: Summary Generation
#------------------------------------------------------------------------------
generate_summary() {
    print_phase 7 "Summary Generation"

    local start_time=$(date +%s)

    print_step "SUMMARY" "Generating deployment summary"

    # Calculate total duration and collect phase durations
    local phase1_duration=$(cat "$LOGS_DIR/.phase1-duration" 2>/dev/null || echo "0")
    local phase2_duration=$(cat "$LOGS_DIR/.phase2-duration" 2>/dev/null || echo "0")
    local phase3_duration=$(cat "$LOGS_DIR/.phase3-duration" 2>/dev/null || echo "0")
    local phase4_duration=$(cat "$LOGS_DIR/.phase4-duration" 2>/dev/null || echo "0")
    local phase5_duration=$(cat "$LOGS_DIR/.phase5-duration" 2>/dev/null || echo "0")
    local phase6_duration=$(cat "$LOGS_DIR/.phase6-duration" 2>/dev/null || echo "0")

    local total_duration=$((phase1_duration + phase2_duration + phase3_duration + phase4_duration + phase5_duration + phase6_duration))
    local total_min=$((total_duration / 60))
    local total_sec=$((total_duration % 60))

    # Check for any failures
    local phase1_exit=$(cat "$LOGS_DIR/.phase1-exit-code" 2>/dev/null || echo "0")
    local phase2_exit=$(cat "$LOGS_DIR/.phase2-exit-code" 2>/dev/null || echo "0")
    local phase3_exit=$(cat "$LOGS_DIR/.phase3-exit-code" 2>/dev/null || echo "0")
    local phase4_exit=$(cat "$LOGS_DIR/.phase4-exit-code" 2>/dev/null || echo "0")
    local phase5_exit=$(cat "$LOGS_DIR/.phase5-exit-code" 2>/dev/null || echo "0")

    local overall_status="SUCCESS"
    if [[ "$phase1_exit" != "0" ]] || [[ "$phase2_exit" != "0" ]] || [[ "$phase3_exit" != "0" ]] || [[ "$phase4_exit" != "0" ]] || [[ "$phase5_exit" != "0" ]]; then
        overall_status="FAILED"
    fi

    # Create JSON summary
    cat > "$LOGS_DIR/deployment-summary.json" <<EOF
{
  "deployment": {
    "timestamp": "$TIMESTAMP",
    "started": "$(cat "$LOGS_DIR/deployment-info.txt" | grep "Started:" | cut -d: -f2-)",
    "completed": "$(date)",
    "status": "$overall_status",
    "total_duration_seconds": $total_duration,
    "total_duration_formatted": "${total_min}m ${total_sec}s"
  },
  "phases": {
    "validation": {
      "duration_seconds": $phase1_duration,
      "exit_code": $phase1_exit,
      "status": "$([[ "$phase1_exit" == "0" ]] && echo "SUCCESS" || echo "FAILED")"
    },
    "cleanup": {
      "duration_seconds": $phase2_duration,
      "exit_code": $phase2_exit,
      "status": "$([[ "$phase2_exit" == "0" ]] && echo "SUCCESS" || echo "FAILED")"
    },
    "deployment": {
      "duration_seconds": $phase3_duration,
      "exit_code": $phase3_exit,
      "status": "$([[ "$phase3_exit" == "0" ]] && echo "SUCCESS" || echo "FAILED")"
    },
    "infrastructure_validation": {
      "duration_seconds": $phase4_duration,
      "exit_code": $phase4_exit,
      "status": "$([[ "$phase4_exit" == "0" ]] && echo "SUCCESS" || echo "FAILED")"
    },
    "post_deploy_test": {
      "duration_seconds": $phase5_duration,
      "exit_code": $phase5_exit,
      "status": "$([[ "$phase5_exit" == "0" ]] && echo "SUCCESS" || echo "FAILED")"
    },
    "log_collection": {
      "duration_seconds": $phase6_duration
    }
  },
  "logs": {
    "directory": "$LOGS_DIR",
    "files": [
      "01-validate.log",
      "02-terraform-apply.log",
      "03-infrastructure-validation.log",
      "04-post-deploy-test.log",
      "05-controller-logs.log",
      "06-worker-logs.log",
      "terraform-outputs.json",
      "deployment-summary.json",
      "full-deployment.log"
    ]
  }
}
EOF

    print_success "Deployment summary saved to: $LOGS_DIR/deployment-summary.json"

    # Combine all logs into single file
    print_step "SUMMARY" "Creating combined log file"
    cat > "$LOGS_DIR/full-deployment.log" <<EOF
================================================================================
Boundary Enterprise - Full Deployment Log
================================================================================
Timestamp: $TIMESTAMP
Overall Status: $overall_status
Total Duration: ${total_min}m ${total_sec}s
================================================================================

EOF

    # Append each phase log
    for log_file in "$LOGS_DIR"/*.log; do
        if [[ "$log_file" != "$LOGS_DIR/full-deployment.log" ]]; then
            echo "" >> "$LOGS_DIR/full-deployment.log"
            echo "========================================" >> "$LOGS_DIR/full-deployment.log"
            echo "$(basename "$log_file")" >> "$LOGS_DIR/full-deployment.log"
            echo "========================================" >> "$LOGS_DIR/full-deployment.log"
            cat "$log_file" >> "$LOGS_DIR/full-deployment.log"
        fi
    done

    print_success "Combined log saved to: $LOGS_DIR/full-deployment.log"

    # Create clean versions of logs (without ANSI color codes)
    print_step "SUMMARY" "Creating clean log files (no color codes)"
    for log_file in "$LOGS_DIR"/*.log; do
        if [[ -f "$log_file" ]] && [[ "$log_file" != *"-clean.log" ]]; then
            strip_colors "$log_file"
        fi
    done

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    print_success "Summary generation completed (${duration}s)"
}

#------------------------------------------------------------------------------
# Print Final Summary
#------------------------------------------------------------------------------
print_final_summary() {
    print_header "Deployment Complete"

    cd test 2>/dev/null || cd "$SCRIPT_DIR"

    local boundary_url=$(terraform output -raw boundary_url 2>/dev/null || echo "")
    local lb_ip=$(terraform output -raw controller_load_balancer_ip 2>/dev/null || echo "")

    echo "Logs Directory: $LOGS_DIR"
    echo ""
    echo "Key Files:"
    echo "  - deployment-summary.json    : Deployment metadata and timing"
    echo "  - terraform-outputs.json     : All terraform outputs"
    echo "  - full-deployment.log        : Combined log from all phases"
    echo "  - boundary-credentials.txt   : Initial admin credentials (if generated)"
    echo ""

    if [[ -n "$boundary_url" ]]; then
        echo "Boundary Access:"
        echo "  URL: $boundary_url"
        echo "  IP:  $lb_ip"
        echo ""
    fi

    if [[ -f "$LOGS_DIR/boundary-credentials.txt" ]]; then
        echo -e "${YELLOW}⚠ Initial admin credentials saved in logs directory${NC}"
        echo -e "${YELLOW}  Delete after saving securely!${NC}"
        echo ""
    fi

    echo "Next Steps:"
    echo "  1. Review deployment summary: cat $LOGS_DIR/deployment-summary.json | jq"
    echo "  2. Check terraform outputs: cat $LOGS_DIR/terraform-outputs.json | jq"
    echo "  3. Access Boundary UI: $boundary_url"
    echo "  4. Review logs if needed: less $LOGS_DIR/full-deployment.log"
    echo ""

    cd "$SCRIPT_DIR"
}

#------------------------------------------------------------------------------
# Main Execution
#------------------------------------------------------------------------------
main() {
    parse_args "$@"

    # Handle --clean-logs flag early and exit
    if [[ "$CLEAN_LOGS" == "true" ]]; then
        clean_logs
        exit 0
    fi

    print_header "Boundary Enterprise - Full Deployment with Logging"

    setup_logs
    print_config

    # Confirm if not dry-run
    if [[ "$DRY_RUN" == "false" ]] && [[ -t 0 ]]; then
        echo ""
        read -p "Proceed with deployment? (yes/no): " -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
            print_warning "Deployment cancelled by user"
            exit 0
        fi
    fi

    # Track overall start time
    DEPLOYMENT_START=$(date +%s)

    # Execute phases
    run_validation || true

    if [[ "$DRY_RUN" == "true" ]]; then
        print_success "Dry run complete (validation only)"
        exit 0
    fi

    run_cleanup || true
    run_deployment || exit 1
    run_infrastructure_validation || true
    run_post_deploy_test || true
    collect_logs
    generate_summary

    # Calculate total time
    DEPLOYMENT_END=$(date +%s)
    TOTAL_TIME=$((DEPLOYMENT_END - DEPLOYMENT_START))
    TOTAL_MIN=$((TOTAL_TIME / 60))
    TOTAL_SEC=$((TOTAL_TIME % 60))

    print_final_summary

    print_success "Total deployment time: ${TOTAL_MIN}m ${TOTAL_SEC}s"
}

# Run main function
main "$@"
