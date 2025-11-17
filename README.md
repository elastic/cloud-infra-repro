# Cloud Infrastructure Scenarios

This repository contains Terraform configurations and automation scripts for creating
cloud infrastructure scenarios on Google Cloud Platform. It currently ships with:

- **VPC Flow Logs**: Generates internal VM traffic and exports subnet flow logs.
- **Network Load Balancer Logs**: Provisions an external TCP/UDP NLB, drives client
  traffic through the forwarding rule, and exports load balancer logs.

## Prerequisites

- Terraform **v1.5+**
- Google provider **v5.0+** (downloaded automatically by Terraform)
- An authenticated `gcloud` session with access to your GCP project
- Make sure you are logged into gcloud in TWO different ways:
  - `gcloud auth login`
  - `gcloud auth application-default login` (for Terraform)
- Go (for traffic generation scripts)
- `jq` (for JSON processing)
- Fish shell **v3.6+** (helper scripts are implemented in fish)

> The helper scripts use a Go traffic runner to connect to instances via SSH
> and generate traffic after Terraform completes.

## Quick Start

1. Copy the example environment file and adjust the values:

   ```bash
   cp config.env.example config.env
   $EDITOR config.env
   ```

   Update `PROJECT_ID`, `REGION`, and `ZONE`. Set `SCENARIO` to `vpc-flow` or `nlb`
   if you plan to run Terraform manually; the helper scripts force the correct value.

### VPC Flow Logs Scenario

```bash
./run.fish generate --scenario=vpc-flow
# wait ~10 minutes for flow logs to aggregate
./run.fish export --scenario=vpc-flow
```

Results are written to `./vpc-fixtures-out/vpc_logs.jsonl`.

### Network Load Balancer Scenario

```bash
./run.fish generate --scenario=nlb
# wait a few minutes for load balancer logs to aggregate
./run.fish export --scenario=nlb
```

Results are written to `./nlb-fixtures-out/nlb_logs.jsonl`.

### Teardown

Destroy whichever scenario is active:

```bash
./run.fish teardown --scenario=vpc-flow --dry-run=false
# or select a different scenario explicitly
./run.fish teardown --scenario=nlb --dry-run=false
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
| `scenario`       | string | `vpc-flow`    | Fixture scenario to deploy (`vpc-flow` or `nlb`).            |

## Outputs

| Name             | Description                                                  |
| ---------------- | ------------------------------------------------------------ |
| `scenario`             | Selected scenario (`vpc-flow` or `nlb`).                   |
| `region`               | Region where the active scenario resources reside.          |
| `zone`                 | Zone used for zonal resources.                               |
| `mig_name`             | (VPC) Managed instance group name consumed by the Go helper.|
| `subnet_name`          | Subnet used for log filtering and traffic generation.        |
| `backend_mig_name`     | (NLB) Managed instance group serving the load balancer.      |
| `client_instance_name` | (NLB) Client VM used to generate load balancer traffic.      |
| `forwarding_rule_name` | (NLB) Forwarding rule backing the load balancer.             |
| `forwarding_rule_ip`   | (NLB) External IP address assigned to the forwarding rule.   |

## Infrastructure Details

### VPC Flow Logs

- **VPC Network**: Custom mode network with a single subnet (`10.10.0.0/20`)
- **VPC Flow Logs**: Enabled with 5-minute aggregation and full metadata sampling
- **Firewall Rules**:
  - Internal traffic (all protocols within the subnet)
  - SSH access (from anywhere)
- **Managed Instance Group**: Regional MIG with 2 Debian 12 instances
- **Traffic Generation**: Automated intra-VPC traffic plus calls to Google Cloud APIs

### Network Load Balancer Logs

- **VPC Network**: Custom mode network with subnet (`10.20.0.0/20`)
- **Backend MIG**: Zonal managed instance group (2 Debian 12 VMs) running a simple HTTP server
- **Health Checks**: TCP health check on port 80 with firewall rules for Google LB ranges
- **Client VM**: Dedicated client instance that generates HTTP and raw TCP traffic
- **Load Balancer**: External TCP/UDP network load balancer with logging (100% sample rate)
- **Firewall Rules**: Internal traffic, SSH access, client-to-backend allow list

## Adding New Scenarios

The repository is structured so additional scenarios can reuse the same tooling:

1. Create a Terraform module under `terraform/modules/<scenario-name>/`.
2. Update `terraform/main.tf`, `variables.tf`, and `outputs.tf` to expose the scenario.
3. Add a `lib/scenarios/<scenario-name>.fish` helper that implements the required \`scenario::\` functions consumed by `run.fish`.
4. Document the workflow in this README.
