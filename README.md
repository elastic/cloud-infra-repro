# Cloud Infrastructure Scenarios

This repository contains Terraform configurations and automation scripts for creating
cloud infrastructure scenarios on Google Cloud Platform. It currently ships with:

- **VPC Flow Logs**: Generates internal VM traffic and exports subnet flow logs.
- **Network Load Balancer Logs**: Provisions a regional external proxy TCP Network Load
  Balancer, drives client traffic through the forwarding rule, and exports connection logs.

## Prerequisites

- Terraform **v1.5+**
- Google provider **v5.0+** (downloaded automatically by Terraform)
- An authenticated `gcloud` session with access to your GCP project
- Make sure you are logged into gcloud in TWO different ways:
  - `gcloud auth login`
  - `gcloud auth application-default login` (for Terraform)
- Fish shell **v3.6+** (the helper scripts are written in fish; bash/zsh are not supported)
- `jq` (for JSON processing)
- `curl` and `netcat` (used to generate NLB traffic from your workstation)
- Go **1.21+** (only required for the VPC flow scenario traffic runner)

> After Terraform completes, the helper scripts automatically generate traffic.
> The VPC flow scenario uses a Go traffic runner over SSH, while the NLB scenario
> drives curl/netcat traffic from your local machine.

> **Warning:** Running either scenario provisions billable Google Cloud resources.
> Proxy Network Load Balancers incur hourly forwarding rule and proxy-only subnet
> costs even when idle. Destroy the scenario as soon as you finish exporting logs.

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

### Destroy

Destroy whichever scenario is active:

```bash
./run.fish destroy --scenario=vpc-flow --dry-run=false
# or select a different scenario explicitly
./run.fish destroy --scenario=nlb --dry-run=false
```

## How It Works

1. **Generate**: `./run.fish generate --scenario=<name>` runs Terraform with the selected scenario, validates outputs, and automatically kicks off traffic generation.
2. **Traffic**:
   - *VPC Flow Logs*: A Go helper connects to MIG instances over SSH to create east-west traffic.
   - *NLB Logs*: The script waits for backend readiness and for the proxy to respond, then fires curl/netcat traffic from the local machine.
3. **Ingestion Delay**: Logs are not immediate. Expect ~10 minutes for VPC flow logs and a few minutes for proxy NLB connection logs.
4. **Export**: `./run.fish export --scenario=<name>` reuses Terraform outputs, applies a default 20-minute window (`START_TIME` = now-20m, `END_TIME` = now), and writes JSON Lines files to `./vpc-fixtures-out` or `./nlb-fixtures-out`.
5. **Destroy**: `./run.fish destroy --scenario=<name>` cleans up the Terraform resources. By default it runs in dry-run mode until you pass `--dry-run=false`.

## Configuration

### Environment Variables

- `START_TIME` / `END_TIME`: UTC timestamps (`YYYY-MM-DDTHH:MM:SSZ`) used when exporting logs. Default is from 20 minutes ago until now.
- `MAX_RESULTS`: Caps log entries returned by `gcloud logging read` (default `2000`).
- `OUTPUT_DIR`: Directory where exports are written (`./vpc-fixtures-out` or `./nlb-fixtures-out` by default).
- `RESOURCE_PREFIX`: Prefix for Terraform resource names (`gcp-fixture` if unset).

### Destroy Options

- `--dry-run` flag controls whether `destroy` issues `terraform plan -destroy` (default) or a full `terraform destroy`.
- To actually delete resources, pass `--dry-run=false`.

## Log Output Format

Both `export` commands produce JSON Lines files (`*.jsonl`). Each line is a complete JSON object that is safe to ingest into downstream tooling.

### Network Load Balancer Logs

- `resource.type="l4_proxy_rule"`
- Key labels include:
  - `project_id`, `network_name`, `region`, `load_balancing_scheme`, `protocol`
  - `forwarding_rule_name`, `target_proxy_name`
  - `backend_target_name`, `backend_target_type`
  - `backend_name`, `backend_type`, `backend_scope`, `backend_scope_type`
- `jsonPayload.connection` records client/server IPs, ports, protocol numbers, byte counts, start/end timestamps, and latency

### VPC Flow Logs

- `resource.type="gce_subnetwork"`
- `jsonPayload` matches the VPC Flow Logs schema (5‑minute aggregation, `reporter`, `connection`, `src/dest` metadata)
- Includes bytes, packets, and compute metadata (instance ID, tags, subnet)

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
- **Proxy-only Subnet**: Dedicated `/24` subnet (`10.20.16.0/24`) with `REGIONAL_MANAGED_PROXY` purpose for the LB control plane
- **Target Proxy**: Regional target TCP proxy resource that fronts the backend service
- **Load Balancer**: Regional external proxy Network Load Balancer (EXTERNAL_MANAGED) using a TCP proxy with 100% connection logging
- **Network Tier**: STANDARD tier addresses to keep costs low during testing
- **Readiness Waits**: Helper script waits up to 5 minutes for backend instances and the proxy to start responding before traffic generation
- **Logging**: Connection logs exported via `resource.type="l4_proxy_rule"` and filtered by forwarding rule name
- **Firewall Rules**: Internal traffic, SSH access, client-to-backend allow list

## Troubleshooting

- **No logs exported yet**: Flow logs take about 10 minutes to appear; proxy NLB connection logs typically take 2–5 minutes. Re-run export or adjust `START_TIME`/`END_TIME`.
- **Load balancer not responding**: Backends might still be initializing. `run.fish` already waits for readiness, but you can confirm status via `gcloud compute instance-groups managed list-instances`.
- **Destroy fails with `resourceInUseByAnotherResource`**: Forwarding rules may still reference the proxy-only subnet. Wait a minute and re-run `./run.fish destroy --scenario=<name> --dry-run=false`.
- **Costs creeping up**: Proxy load balancers incur per-hour forwarding rule and proxy-only subnet charges. Always destroy the scenario after exporting the data you need.

## Adding New Scenarios

Note that usage of an LLM is highly recommended for this repo.
The repository is structured so additional scenarios can reuse the same tooling:

1. Create a Terraform module under `terraform/modules/<scenario-name>/`.
2. Update `terraform/main.tf`, `variables.tf`, and `outputs.tf` to expose the scenario.
3. Add a `lib/scenarios/<scenario-name>.fish` helper that implements:
   - `scenario::validate_outputs` — pulls required Terraform outputs into shell variables.
   - `scenario::run_traffic` — generates the scenario-specific traffic after Terraform apply.
   - `scenario::export_logs` — runs the correct `gcloud logging read` query and writes JSONL.
   - `scenario::print_next_steps` — displays post-run instructions (e.g., wait times, destroy reminders).
4. Document the workflow in this README.
