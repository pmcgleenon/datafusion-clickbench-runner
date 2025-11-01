#!/bin/bash 
# Main entry point for DataFusion ClickBench automation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
CLICKBENCH_REPO="https://github.com/ClickHouse/ClickBench.git"
#INSTANCE_TYPES=("c6a.xlarge" "c6a.2xlarge" "c6a.4xlarge" "c8g.4xlarge")
INSTANCE_TYPES=("c6a.2xlarge" "c6a.4xlarge" "c8g.4xlarge")
DATAFUSION_VARIANTS=("datafusion" "datafusion-partitioned")

print_usage() {
    cat << EOF
DataFusion ClickBench Automation

Usage: $0 [OPTIONS] COMMAND

Commands:
    setup           Launch AWS instances for benchmarking
    benchmark       Run benchmarks on existing instances
    collect         Collect results from instances
    cleanup         Terminate instances and remove security group
    full            Run complete benchmark cycle (setup -> benchmark -> collect -> cleanup)

Options:
    --variants      Comma-separated list of variants (default: datafusion,datafusion-partitioned)
    --instances     Comma-separated list of instance types (default: all)
    --datafusion-ref Git reference for DataFusion (default: main)
    --enable-native-opts Enable native CPU optimizations (default: true)
    --run-id        Unique identifier for this run (default: auto-generated)
    --dry-run       Show what would be done without executing

Examples:
    $0 full                                    # Run complete benchmark on all instances
    $0 --variants datafusion benchmark        # Run only standard datafusion variant
    $0 --instances c6a.4xlarge,c8g.4xlarge benchmark   # Run on specific instances
    $0 --datafusion-ref v49.0.0 full         # Benchmark specific DataFusion version

EOF
}

parse_arguments() {
    VARIANTS=("${DATAFUSION_VARIANTS[@]}")
    INSTANCES=("${INSTANCE_TYPES[@]}")
    DATAFUSION_REF="main"
    ENABLE_NATIVE_OPTS=true
    RUN_ID="$(date +%Y%m%d-%H%M%S)"
    DRY_RUN=false
    COMMAND=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --variants)
                IFS=',' read -ra VARIANTS <<< "$2"
                shift 2
                ;;
            --instances)
                IFS=',' read -ra INSTANCES <<< "$2"
                shift 2
                ;;
            --datafusion-ref)
                DATAFUSION_REF="$2"
                shift 2
                ;;
            --enable-native-opts)
                ENABLE_NATIVE_OPTS="$2"
                shift 2
                ;;
            --run-id)
                RUN_ID="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            setup|benchmark|collect|cleanup|full)
                COMMAND="$1"
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

    if [[ -z "$COMMAND" ]]; then
        echo "Error: No command specified"
        print_usage
        exit 1
    fi
}

validate_prerequisites() {
    echo "Validating prerequisites..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        echo "❌ Error: AWS CLI not found"
        echo "Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "❌ Error: AWS credentials not configured"
        echo "Run: aws configure"
        exit 1
    fi

    # Check Python
    if ! command -v python3 &> /dev/null; then
        echo "❌ Error: Python 3 not found"
        exit 1
    fi

    # Check PyYAML
    if ! python3 -c "import yaml" &> /dev/null; then
        echo "❌ Error: PyYAML not installed"
        echo "Run: pip3 install -r requirements.txt"
        exit 1
    fi

    echo "✅ Prerequisites validated"
}

load_config() {
    if [[ -f "$PROJECT_DIR/config/aws-config.yml" ]]; then
        # Parse YAML config (simplified parsing)
        eval $(python3 -c "
import yaml
with open('$PROJECT_DIR/config/aws-config.yml') as f:
    config = yaml.safe_load(f)
    aws = config.get('aws', {})
    print(f'export AWS_REGION={aws.get(\"region\", \"us-west-2\")}')
    print(f'export AWS_KEY_NAME={aws.get(\"key_name\", \"\")}')
    print(f'export AWS_PRIVATE_KEY_FILE={aws.get(\"private_key_file\", \"\")}')
    print(f'export AWS_SECURITY_GROUP={aws.get(\"security_group\", \"\")}')
    print(f'export AMI_ID={config.get(\"instances\", {}).get(\"ami_id\", \"ami-0c02fb55956c7d316\")}')
")
    else
        echo "❌ Error: Configuration file not found"
        echo "Run: ./scripts/setup-environment.sh"
        exit 1
    fi

    # Validate key configuration
    if [[ "$AWS_KEY_NAME" == "YOUR_EC2_KEY_PAIR_NAME" || -z "$AWS_KEY_NAME" ]]; then
        echo "❌ Error: EC2 key pair not configured"
        echo "Edit config/aws-config.yml and set your key_name"
        exit 1
    fi

    # Security group will be managed by Ansible playbooks
}

setup_instances() {
    echo "Setting up instances for variants: ${VARIANTS[*]}"
    echo "Instance types: ${INSTANCES[*]}"
    echo "DataFusion ref: $DATAFUSION_REF"
    echo "Native optimizations: $ENABLE_NATIVE_OPTS"
    echo "Run ID: $RUN_ID"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would launch instances and run setup playbook"
        return
    fi

    # Launch instances using Ansible (handles security group, instance launch, and SSH wait)
    echo "Launching instances with Ansible..."

    # Convert instance types to proper JSON array
    local instances_json="["
    local first=true
    for instance in "${INSTANCES[@]}"; do
        if [[ "$first" == "true" ]]; then
            instances_json+="\"$instance\""
            first=false
        else
            instances_json+=",\"$instance\""
        fi
    done
    instances_json+="]"

    ansible-playbook -i "localhost," \
        "$PROJECT_DIR/ansible/playbooks/simple-launch.yml" \
        --extra-vars "instance_types=$instances_json ami_id=$AMI_ID key_name=$AWS_KEY_NAME region=$AWS_REGION run_id=$RUN_ID" \
        --connection local

    # Run setup playbook on launched instances
    ansible-playbook -i "$PROJECT_DIR/ansible/inventory/aws_ec2.yml" \
        "$PROJECT_DIR/ansible/playbooks/setup-instance.yml" \
        --private-key "$AWS_PRIVATE_KEY_FILE" \
        --extra-vars "datafusion_ref=$DATAFUSION_REF clickbench_repo=$CLICKBENCH_REPO enable_native_opts=$ENABLE_NATIVE_OPTS run_id=$RUN_ID"
}

run_benchmarks() {
    echo "Running benchmarks for variants: ${VARIANTS[*]}"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would run benchmark playbook for each variant"
        return
    fi

    for variant in "${VARIANTS[@]}"; do
        echo "Running benchmarks for $variant..."

        if ! ansible-playbook -i "$PROJECT_DIR/ansible/inventory/aws_ec2.yml" \
            "$PROJECT_DIR/ansible/playbooks/run-datafusion.yml" \
            --private-key "$AWS_PRIVATE_KEY_FILE" \
            --extra-vars "datafusion_variant=$variant datafusion_ref=$DATAFUSION_REF run_id=$RUN_ID"; then
            echo "❌ Error: Benchmark failed for variant $variant"
            exit 1
        else
            echo "✅ Benchmark completed successfully for $variant"
        fi
    done
}

collect_results() {
    echo "Collecting results..."

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would collect and process results"
        return
    fi

    # Create results directory with timestamp
    RESULTS_DIR="$PROJECT_DIR/results/${RUN_ID}"
    mkdir -p "$RESULTS_DIR"

    # Collect results from all instances using Ansible
    ansible-playbook -i "$PROJECT_DIR/ansible/inventory/aws_ec2.yml" \
        "$PROJECT_DIR/ansible/playbooks/collect-results.yml" \
        --private-key "$AWS_PRIVATE_KEY_FILE" \
        --extra-vars "local_results_dir=$RESULTS_DIR run_id=$RUN_ID"

    echo "Results saved to: $RESULTS_DIR"
    echo "Ready to submit to ClickBench repository"
}

cleanup_instances() {
    echo "Cleaning up instances and security group..."

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would run comprehensive environment teardown including security group"
        ansible-playbook -i "localhost," \
            "$PROJECT_DIR/ansible/playbooks/simple-teardown.yml" \
            --extra-vars "remove_security_group=true region=$AWS_REGION" \
            --connection local --check
        return
    fi

    # Run comprehensive teardown including security group removal using Ansible
    ansible-playbook -i "localhost," \
        "$PROJECT_DIR/ansible/playbooks/simple-teardown.yml" \
        --extra-vars "remove_security_group=true region=$AWS_REGION" \
        --connection local
}


# Main execution
parse_arguments "$@"
validate_prerequisites
load_config

case "$COMMAND" in
    "setup")
        setup_instances
        ;;
    "benchmark")
        run_benchmarks
        ;;
    "collect")
        collect_results
        ;;
    "cleanup")
        cleanup_instances
        ;;
    "full")
        setup_instances
        run_benchmarks
        collect_results
        cleanup_instances
        ;;
esac

echo "DataFusion benchmark automation completed successfully!"
