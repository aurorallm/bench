# Linux Benchmark Comparison
# Bash equivalents of BenchmarkComparison.psm1 - requires jq

read_benchmark_result() {
    local path="$1"
    jq '.' "$path" 2>/dev/null
}

write_generic_comparison() {
    local results_json="$1"
    local output_path="$2"
    local rate="$3"
    local duration="$4"
    local model="$5"
    local endpoint="$6"

    local names
    names=$(echo "$results_json" | jq -r 'keys | join(" ")')
    local base_name
    base_name=$(echo "$names" | awk '{print $1}')

    local machine_info
    machine_info=$(cat <<JSON
{
  "hostname": "$(hostname)",
  "os": "$(uname -a)",
  "arch": "$(uname -m)",
  "logical_processors": $(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
}
JSON
)

    local deltas_json="{"
    local first=true
    local base_data
    base_data=$(echo "$results_json" | jq -c ".[\"$base_name\"]")
    for name in $names; do
        [ "$name" = "$base_name" ] && continue
        local other_data
        other_data=$(echo "$results_json" | jq -c ".[\"$name\"]")
        [ "$first" = true ] && first=false || deltas_json+=", "
        deltas_json+="\"${name}_vs_${base_name}\": "
        deltas_json+=$(jq -n --argjson base "$base_data" --argjson other "$other_data" '{
            throughput_rps: (($other.throughput_rps // 0) - ($base.throughput_rps // 0)),
            mean_latency_ms: (($other.mean_latency_ms // 0) - ($base.mean_latency_ms // 0)),
            p50_latency_ms: (($other.p50_latency_ms // 0) - ($base.p50_latency_ms // 0)),
            p90_latency_ms: (($other.p90_latency_ms // 0) - ($base.p90_latency_ms // 0)),
            p95_latency_ms: (($other.p95_latency_ms // 0) - ($base.p95_latency_ms // 0)),
            p99_latency_ms: (($other.p99_latency_ms // 0) - ($base.p99_latency_ms // 0)),
            p999_latency_ms: (($other.p999_latency_ms // 0) - ($base.p999_latency_ms // 0)),
            max_latency_ms: (($other.max_latency_ms // 0) - ($base.max_latency_ms // 0)),
            success_rate: (($other.success_rate // 0) - ($base.success_rate // 0)),
            allocs_per_op: (($other.allocs_per_op // 0) - ($base.allocs_per_op // 0)),
            bytes_per_op: (($other.bytes_per_op // 0) - ($base.bytes_per_op // 0))
        }')
    done
    deltas_json+="}"

    local comparison
    comparison=$(cat <<COMPJSON
{
  "metadata": {
    "generated_at": "$(date -Iseconds)",
    "gateways": $(echo "$names" | jq -R 'split(" ")'),
    "baseline": "$base_name",
    "tool": "aurora-bench-cli (POSIX-timed)",
    "machine": $machine_info,
    "config": {
      "rate": $rate,
      "duration_seconds": $duration,
      "model": "$model",
      "endpoint": "$endpoint"
    }
  },
  "results": $results_json,
  "deltas": $deltas_json
}
COMPJSON
)

    echo "$comparison" | jq '.' > "$output_path"
    echo "Comparison written to: $output_path"
}

write_comparison_summary() {
    local path="$1"
    if [ ! -f "$path" ]; then
        echo "Comparison file not found: $path"
        return 1
    fi

    local data
    data=$(jq '.' "$path" 2>/dev/null) || return 1

    local names gateway_count col_width table_width
    names=$(echo "$data" | jq -r '.metadata.gateways[]')
    gateway_count=$(echo "$data" | jq -r '.metadata.gateways | length')
    col_width=18
    [ "$gateway_count" -gt 1 ] && col_width=$(( (60 - 34) / gateway_count ))
    [ "$col_width" -lt 14 ] && col_width=14
    table_width=$(( 36 + col_width * gateway_count ))

    local sep_bar dashes_bar
    sep_bar=$(printf "%*s" "$table_width" "" | tr ' ' '=')
    dashes_bar=$(printf "%*s" "$table_width" "" | tr ' ' '-')

    echo ""
    echo "  $sep_bar"
    printf "  |%*s Benchmark Comparison %*s|\n" $(( (table_width - 22) / 2 )) "" $(( (table_width - 22 + 1) / 2 )) ""
    echo "  $sep_bar"
    echo ""

    local rate_str duration_str model_str endpoint_str host_str cpu_str
    rate_str=$(echo "$data" | jq -r '.metadata.config.rate')
    duration_str=$(echo "$data" | jq -r '.metadata.config.duration_seconds')
    model_str=$(echo "$data" | jq -r '.metadata.config.model')
    endpoint_str=$(echo "$data" | jq -r '.metadata.config.endpoint')
    host_str=$(echo "$data" | jq -r '.metadata.machine.hostname')
    cpu_str=$(echo "$data" | jq -r '.metadata.machine.logical_processors')

    echo "  Config: $rate_str req/s x ${duration_str}s"
    echo "  Model: $model_str | Endpoint: $endpoint_str"
    echo "  Host: $host_str ($cpu_str CPUs)"
    echo ""

    printf "  %-34s" "Metric"
    for n in $names; do
        printf "  %*s" "$col_width" "$n"
    done
    echo ""
    echo "  $dashes_bar"

    _summary_row "Throughput (req/s)" '.["results"]["%s"]["throughput_rps"]' "%.2f" "$data" "$names" "$col_width"
    _summary_row "Mean latency (ms)" '.["results"]["%s"]["mean_latency_ms"]' "%.3f" "$data" "$names" "$col_width"
    _summary_row "P50 latency (ms)" '.["results"]["%s"]["p50_latency_ms"]' "%.3f" "$data" "$names" "$col_width"
    _summary_row "P90 latency (ms)" '.["results"]["%s"]["p90_latency_ms"]' "%.3f" "$data" "$names" "$col_width"
    _summary_row "P95 latency (ms)" '.["results"]["%s"]["p95_latency_ms"]' "%.3f" "$data" "$names" "$col_width"
    _summary_row "P99 latency (ms)" '.["results"]["%s"]["p99_latency_ms"]' "%.3f" "$data" "$names" "$col_width"
    _summary_row "P999 latency (ms)" '.["results"]["%s"]["p999_latency_ms"]' "%.3f" "$data" "$names" "$col_width"
    _summary_row "Max latency (ms)" '.["results"]["%s"]["max_latency_ms"]' "%.3f" "$data" "$names" "$col_width"
    _summary_row "Success %" '.["results"]["%s"]["success_rate"]' "%.2f" "$data" "$names" "$col_width"
    _summary_row "Allocs/op" '.["results"]["%s"]["allocs_per_op"]' "%.1f" "$data" "$names" "$col_width"
    _summary_row "Bytes/op" '.["results"]["%s"]["bytes_per_op"]' "%.0f" "$data" "$names" "$col_width"
    _summary_row "Requests" '.["results"]["%s"]["requests"]' "%.0f" "$data" "$names" "$col_width"

    printf "  %-34s" "Status codes (200/4xx/5xx/err)"
    for n in $names; do
        local s200 s4xx s5xx errc
        s200=$(echo "$data" | jq -r ".results.\"$n\".status_200 // 0")
        s4xx=$(echo "$data" | jq -r ".results.\"$n\".status_4xx // 0")
        s5xx=$(echo "$data" | jq -r ".results.\"$n\".status_5xx // 0")
        errc=$(echo "$data" | jq -r "[.results.\"$n\".error_breakdown[]?.count] | add // 0")
        printf "  %*s" "$col_width" "$s200/$s4xx/$s5xx/$errc"
    done
    echo ""

    for n in $names; do
        echo "$data" | jq -r ".results.\"$n\".error_breakdown[]? | select(.count > 0) | \"  [\(.count)x] \(.message)\"" 2>/dev/null | while read -r line; do
            printf "  %-34s  %s\n" "  $n errors" "$line"
        done
    done
    echo ""

    local baseline
    baseline=$(echo "$data" | jq -r '.metadata.baseline')
    local delta_names
    delta_names=$(echo "$data" | jq -r '.deltas | keys | join(" ")')
    if [ -n "$delta_names" ]; then
        echo "  Deltas (vs $baseline):"
        echo "  $dashes_bar"

        for metric in throughput_rps mean_latency_ms p50_latency_ms p90_latency_ms p95_latency_ms p99_latency_ms p999_latency_ms max_latency_ms success_rate allocs_per_op bytes_per_op; do
            local label
            label=$(echo "$metric" | sed 's/_rps/ (rps)/; s/_latency_ms/ (ms)/; s/_per_op/\/op/; s/_/ /g')
            printf "  %-34s" "  $label"
            for dn in $delta_names; do
                local dv
                dv=$(echo "$data" | jq -r ".deltas[\"$dn\"].$metric // empty")
                if [ -n "$dv" ]; then
                    printf "  %*s" "$col_width" "$(printf "%.3f" "$dv")"
                else
                    printf "  %*s" "$col_width" "N/A"
                fi
            done
            echo ""
        done
        echo ""
    fi

    echo "  $sep_bar"
    echo ""
}

_summary_row() {
    local label="$1" jqpath="$2" fmt="$3" data="$4" names="$5" col_width="$6"
    printf "  %-34s" "$label"
    for n in $names; do
        local p val
        p=$(printf "$jqpath" "$n")
        val=$(echo "$data" | jq -r "$p // 0")
        if [ -n "$val" ]; then
            printf "  %*s" "$col_width" "$(printf "$fmt" "$val")"
        else
            printf "  %*s" "$col_width" "N/A"
        fi
    done
    echo ""
}
