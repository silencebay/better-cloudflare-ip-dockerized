#!/bin/bash
set -e

# Source the logging library
source "$(dirname "$0")/../lib/logging.sh"

# Configuration with environment variables and defaults
WORK_DIR=${WORK_DIR:-/usr/local/bin/CloudflareSpeedTest}
RESULT_FILE=${RESULT_FILE:-/tmp/result.csv}
TOP_N=${TOP_N:-10}
OUTPUT_DIR=${OUTPUT_DIR:-/data}

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Validate work directory
if [ ! -d "$WORK_DIR" ]; then
    fatal "Work directory $WORK_DIR does not exist"
fi

# Change to work directory
cd "$WORK_DIR" || fatal "Failed to change to work directory $WORK_DIR"

# Run speed test
info "Starting CloudflareSpeedTest with args: $ARGS"
./CloudflareST $ARGS -o "$RESULT_FILE"

if [ ! -f "$RESULT_FILE" ]; then
    fatal "Speed test result file $RESULT_FILE not found"
fi

# Extract best IPs
info "Extracting top $TOP_N IPs from results"
best_ips=$(tail -n +2 "$RESULT_FILE" | head -n "$TOP_N" | awk -F, '{print $1}')

if [ -z "$best_ips" ]; then
    fatal "No IPs found in result file"
fi

# Save all IPs
echo "$best_ips" > "$OUTPUT_DIR/ips.txt"
info "Saved $TOP_N best IPs to $OUTPUT_DIR/ips.txt"

# Separate IPv4 and IPv6 addresses
info "Separating IPv4 and IPv6 addresses"
echo "$best_ips" | grep -v ":" > "$OUTPUT_DIR/ips-v4.txt" || true
echo "$best_ips" | grep ":" > "$OUTPUT_DIR/ips-v6.txt" || true

# Print statistics
ipv4_count=$(wc -l < "$OUTPUT_DIR/ips-v4.txt")
ipv6_count=$(wc -l < "$OUTPUT_DIR/ips-v6.txt")

info "Results summary:"
info "- Total IPs: $TOP_N"
info "- IPv4 addresses: $ipv4_count (saved to $OUTPUT_DIR/ips-v4.txt)"
info "- IPv6 addresses: $ipv6_count (saved to $OUTPUT_DIR/ips-v6.txt)"

# Show sample of results
info "Sample of best IPs:"
head -n 3 "$OUTPUT_DIR/ips.txt" | while read -r ip; do
    grep "$ip" "$RESULT_FILE"
done
