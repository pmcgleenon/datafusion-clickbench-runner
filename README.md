# DataFusion ClickBench Runner

Automated benchmarking tool for Apache DataFusion against the ClickBench dataset.


## Quick Start

```bash
# 1. Clone and setup
git clone https://github.com/pmcgleenon/datafusion-clickbench-runner.git
cd datafusion-clickbench-runner
./scripts/setup-environment.sh

# 2. Configure AWS (one-time)
cp config/aws-config.yml.example config/aws-config.yml
# Edit with your AWS settings

# 3. Run complete benchmark
./scripts/run-benchmarks.sh full

# 4. Submit results to ClickBench
# Follow instructions in results/TIMESTAMP/SUBMISSION_GUIDE.md
```

## Prerequisites

- AWS account with EC2 permissions
- AWS CLI configured
- Python 3.8+ with pip
- 15-30 minutes for complete benchmark run

### Use Specific Instance Types
```bash
./scripts/run-benchmarks.sh --instances c6a.4xlarge,c8g.4xlarge full
```

### Dry Run (See What Would Happen)
```bash
./scripts/run-benchmarks.sh --dry-run full
```

## 🤝 Contributing

We welcome contributions! See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for guidelines.

## 📄 License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
