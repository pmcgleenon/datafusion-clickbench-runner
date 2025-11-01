#!/bin/bash
# One-time environment setup script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Setting up DataFusion ClickBench Runner environment..."

# Check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        echo "Error: AWS CLI not found. Please install it first."
        echo "Visit: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        echo "Error: AWS credentials not configured."
        echo "Run: aws configure"
        exit 1
    fi

    # Check Python
    if ! command -v python3 &> /dev/null; then
        echo "Error: Python 3 not found. Please install Python 3.8 or later."
        exit 1
    fi

    echo "✅ Prerequisites check passed"
}

# Install Python dependencies
install_python_deps() {
    echo "Installing Python dependencies..."

    # Install from requirements file
    #pip3 install -r "$PROJECT_DIR/requirements.txt"

    # Install Ansible collections
    ansible-galaxy collection install amazon.aws

    echo "✅ Python dependencies installed"
}

# Setup configuration
setup_config() {
    echo "Setting up configuration..."

    # Copy example config if it doesn't exist
    if [[ ! -f "$PROJECT_DIR/config/aws-config.yml" ]]; then
        echo "No AWS configuration found. Creating automatically..."
        echo "- Detecting your current IP address"
        echo "- Creating security group with SSH access from your IP only"
        echo "- Setting up AWS configuration"

        "$SCRIPT_DIR/setup-security-group.sh"
        echo "✅ AWS security group and configuration created"
        echo "⚠️  Don't forget to add your EC2 key pair name to config/aws-config.yml"
    else
        echo "✅ Configuration already exists"

        # Check if security group is configured
        if grep -q "YOUR_SECURITY_GROUP" "$PROJECT_DIR/config/aws-config.yml" 2>/dev/null; then
            echo "⚠️  Security group not configured yet"
            echo "Run: ./scripts/setup-security-group.sh"
        fi
    fi
}

# Validate setup
validate_setup() {
    echo "Validating setup..."

    # Test Ansible
    if ! ansible --version &> /dev/null; then
        echo "Error: Ansible not properly installed"
        exit 1
    fi

    # Test AWS access
    if ! aws ec2 describe-regions --region us-east-1 &> /dev/null; then
        echo "Error: Cannot access AWS EC2. Check credentials and permissions."
        exit 1
    fi

    echo "✅ Setup validation passed"
}

# Display next steps
show_next_steps() {
    cat << EOF

🎉 Setup complete!

Next steps:
1. Edit config/aws-config.yml if you want to override any settings:
   - AWS region
   - EC2 key pair name (will be created automatically)

2. Run a test benchmark:
   ./scripts/run-benchmarks.sh --dry-run full

3. Run full benchmark:
   ./scripts/run-benchmarks.sh full

For help: ./scripts/run-benchmarks.sh --help

EOF
}

# Main execution
main() {
    check_prerequisites
    install_python_deps
    setup_config
    validate_setup
    show_next_steps
}

main "$@"
