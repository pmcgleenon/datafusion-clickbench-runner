#!/bin/bash
# Comprehensive environment teardown for DataFusion ClickBench
# This is a wrapper around the Ansible teardown playbook

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

print_usage() {
    cat << EOF
DataFusion ClickBench Environment Teardown

This script safely removes all AWS resources created by the benchmark automation:
- Terminates all running benchmark instances
- Optionally removes the security group
- Cleans up temporary files and configurations

Usage: $0 [OPTIONS]

Options:
    --region REGION         AWS region (default: from config or us-west-2)
    --keep-security-group   Don't delete the security group (default: keep)
    --remove-security-group Delete the security group too
    --force                 Skip confirmation prompts
    --dry-run              Show what would be deleted without deleting

Examples:
    $0                                    # Terminate instances only
    $0 --remove-security-group           # Remove everything including security group
    $0 --dry-run                         # Show what would be removed
    $0 --force --remove-security-group   # Remove everything without prompts

EOF
}

load_config() {
    if [[ -f "$PROJECT_DIR/config/aws-config.yml" ]]; then
        eval $(python3 -c "
import yaml
try:
    with open('$PROJECT_DIR/config/aws-config.yml') as f:
        config = yaml.safe_load(f)
        aws = config.get('aws', {})
        print(f'export AWS_REGION=\"{aws.get(\"region\", \"us-west-2\")}\"')
except Exception as e:
    print('export AWS_REGION=\"us-west-2\"')
")
    else
        export AWS_REGION="us-west-2"
    fi
}

run_teardown() {
    local region="$1"
    local remove_sg="$2"
    local dry_run="$3"
    local force="$4"

    # Prepare Ansible extra vars
    local extra_vars="region=$region remove_security_group=$remove_sg"

    # Prepare Ansible options
    local ansible_opts=""
    if [[ "$dry_run" == "true" ]]; then
        ansible_opts="--check"
    fi

    echo "=== DataFusion ClickBench Environment Teardown ==="
    echo ""

    # Show what will be done unless forced
    if [[ "$force" != "true" && "$dry_run" != "true" ]]; then
        echo "⚠️  This will terminate all DataFusion benchmark instances in $region"
        if [[ "$remove_sg" == "true" ]]; then
            echo "⚠️  This will also delete the security group"
        fi
        echo ""

        read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Teardown cancelled"
            exit 0
        fi
    fi

    # Run Ansible teardown playbook
    ansible-playbook -i "localhost," \
        "$PROJECT_DIR/ansible/playbooks/simple-teardown.yml" \
        --extra-vars "$extra_vars" \
        --connection local \
        $ansible_opts
}

# Parse arguments
REGION=""
REMOVE_SG=false
FORCE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            REGION="$2"
            shift 2
            ;;
        --keep-security-group)
            REMOVE_SG=false
            shift
            ;;
        --remove-security-group)
            REMOVE_SG=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Load configuration
load_config

# Use provided region or default from config
REGION="${REGION:-$AWS_REGION}"

# Check prerequisites
if ! command -v ansible-playbook &> /dev/null; then
    echo "❌ Error: Ansible not found"
    echo "Run: pip3 install -r requirements.txt"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo "❌ Error: AWS CLI not found"
    exit 1
fi

if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ Error: AWS credentials not configured"
    exit 1
fi

# Run teardown via Ansible
run_teardown "$REGION" "$REMOVE_SG" "$DRY_RUN" "$FORCE"
