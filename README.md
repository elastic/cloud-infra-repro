# Cloud Infrastructure Scenarios

This repository contains Terraform configurations and automation scripts for creating
various cloud infrastructure scenarios. Currently, it includes a VPC flow logs scenario
for Google Cloud Platform that provisions infrastructure, generates network traffic,
and exports logs for analysis or testing purposes.

## Prerequisites

- Terraform **v1.5+**
- Google provider **v5.0+** (downloaded automatically by Terraform)
- An authenticated `gcloud` session with access to your GCP project
- Make sure you are logged into gcloud in TWO different ways:
  - `gcloud auth login`
  - `gcloud auth application-default login` (for Terraform)
- Go (for traffic generation scripts)
- `jq` (for JSON processing)

> The helper scripts use a Go traffic runner to connect to instances via SSH
> and generate traffic after Terraform completes.

## Quick Start

### VPC Flow Logs Scenario

1. Copy the example environment file and adjust the values:

   ```bash
   cp vpc_flow_fixtures.env.example vpc_flow_fixtures.env
   $EDITOR vpc_flow_fixtures.env
   ```

2. Generate infrastructure and traffic:

   ```bash
   ./generate_vpc_flow_fixtures.sh
   ```

   This will:
   - Provision a VPC network with flow logging enabled
   - Create a managed instance group with 2 VMs
   - Generate network traffic between instances
   - Generate traffic to Google Cloud APIs

3. Export logs (wait ~10 minutes after traffic generation for logs to aggregate):

   ```bash
   ./export_vpc_flow_logs.sh
   ```

   Logs will be exported to `./vpc-fixtures-out/vpc_logs.jsonl`

4. Tear everything down when finished:

   ```bash
   ./teardown_vpc_flow_fixtures.sh --dry-run=false
   ```

## Manual Terraform Usage

The wrapper scripts handle the common workflow, but you can run Terraform
directly for debugging or customization:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your project/region/zone/prefix

terraform init
terraform plan
terraform apply

# ... run helper scripts as needed ...

terraform destroy
```

The `terraform.tfvars` file (stored in `terraform/`) drives both manual
runs and the wrapper scripts. If you invoke the scripts, they will respect any
existing `terraform.tfvars`.

## Variables

| Name             | Type   | Default       | Description                                                  |
| ---------------- | ------ | ------------- | ------------------------------------------------------------ |
| `project_id`     | string | _(required)_  | Google Cloud project that hosts the infrastructure.          |
| `region`         | string | _(required)_  | Region for the regional managed instance group.              |
| `zone`           | string | _(required)_  | Default zone used by the provider for zonal API operations.  |
| `resource_prefix`| string | `gcp-fixture` | Prefix applied to all Terraform-managed resources.           |

## Outputs

| Name             | Description                                                  |
| ---------------- | ------------------------------------------------------------ |
| `region`         | Region where the managed instance group resides.             |
| `mig_name`       | Managed instance group name consumed by the Go helper.       |
| `subnet_name`    | Subnet used for log filtering and traffic generation.        |

## Infrastructure Details

The VPC flow logs scenario provisions:

- **VPC Network**: Custom mode network with a single subnet (10.10.0.0/20)
- **VPC Flow Logs**: Enabled on the subnet with 5-minute aggregation intervals
- **Firewall Rules**: 
  - Internal traffic (all protocols within subnet)
  - SSH access (from anywhere)
- **Managed Instance Group**: 2 instances running Debian 12
- **Traffic Generation**: Automated traffic between instances and to Google Cloud APIs

## Adding New Scenarios

This repository is designed to be extended with additional cloud infrastructure
scenarios. To add a new scenario:

1. Create a new Terraform configuration directory (e.g., `terraform/scenarios/my-scenario/`)
2. Add corresponding automation scripts in the root directory
3. Document the scenario in this README
