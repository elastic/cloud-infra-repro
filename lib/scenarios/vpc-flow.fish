# Scenario helpers for the VPC flow logs fixture.

function scenario::validate_outputs -a tf_output_file
  set -gx MIG_NAME (jq -r '.mig_name.value' "$tf_output_file")
  set -gx REGION_OUTPUT (jq -r '.region.value' "$tf_output_file")
  set -gx SUBNET_NAME (jq -r '.subnet_name.value' "$tf_output_file")

  if test -z "$MIG_NAME" -o "$MIG_NAME" = "null"
    printf 'Failed to retrieve managed instance group name from Terraform outputs.\n' >&2
    return 1
  end

  for output_name in REGION_OUTPUT SUBNET_NAME
    set -l value (eval printf '%s' "\$$output_name")
    if test -z "$value" -o "$value" = "null"
      printf 'Missing Terraform output: %s\n' "$output_name" >&2
      return 1
    end
  end
end

function scenario::run_traffic -a script_dir
  common::log "Generating traffic from instances..."
  go run "$script_dir/internal/fixtures/mig_traffic_runner" \
    --mig-name "$MIG_NAME" \
    --region "$REGION_OUTPUT" \
    --project-id "$PROJECT_ID" \
    --generate-traffic
end

function scenario::print_next_steps
  printf '\nNext steps:\n'
  printf '  - Allow ~10 minutes for VPC flow logs to ingest (aggregation interval 5 min).\n'
  printf '  - Run `./run.fish export --scenario=%s` to capture relevant entries.\n' "$SCENARIO"
  printf '  - Remember to clean up resources with run.fish destroy --scenario=%s when finished.\n\n' "$SCENARIO"
end

function scenario::__ensure_time_defaults
  if not set -q START_TIME; or test -z "$START_TIME"
    if date -u -d '20 minutes ago' >/dev/null 2>&1
      set -gx START_TIME (date -u -d '20 minutes ago' +%Y-%m-%dT%H:%M:%SZ)
    else
      set -gx START_TIME (TZ=UTC date -u -v -20M +%Y-%m-%dT%H:%M:%SZ)
    end
  end

  if not set -q END_TIME; or test -z "$END_TIME"
    if date -u >/dev/null 2>&1
      set -gx END_TIME (date -u +%Y-%m-%dT%H:%M:%SZ)
    else
      set -gx END_TIME (TZ=UTC date +%Y-%m-%dT%H:%M:%SZ)
    end
  end

  if not set -q MAX_RESULTS
    set -gx MAX_RESULTS 2000
  end
end

function scenario::export_logs -a tf_output_file
  set -l subnet_name (jq -r '.subnet_name.value' "$tf_output_file")

  if test -z "$subnet_name" -o "$subnet_name" = "null"
    printf 'Missing Terraform output: subnet_name\n' >&2
    return 1
  end

  scenario::__ensure_time_defaults

  if not set -q OUTPUT_DIR
    set -gx OUTPUT_DIR ./vpc-fixtures-out
  end
  mkdir -p "$OUTPUT_DIR"

  set -l agg_output "$OUTPUT_DIR/vpc_logs.jsonl"
  set -l subnet_filter "resource.labels.subnetwork_name=\"$subnet_name\""
  set -l time_filter "timestamp >= \"$START_TIME\" AND timestamp <= \"$END_TIME\""

  common::log "Exporting aggregated VPC flow logs to $OUTPUT_DIR"
  common::log "Using subnet $subnet_name"

  gcloud logging read "$subnet_filter AND $time_filter" \
    --format=json \
    --project "$PROJECT_ID" \
    --limit="$MAX_RESULTS" >"$agg_output"
  or return 1

  common::log "Results written to $agg_output"

  printf '\nReview the candidate files to locate log entries with the desired fields.\n'
  printf 'Suggested commands:\n'
  printf '  jq '"'"'.["jsonPayload"]["round_trip_time"]'"'"' "$agg_output"\n'
  printf '  jq '"'"'.["jsonPayload"]["src_google_service"]'"'"' "$agg_output"\n\n'
end
