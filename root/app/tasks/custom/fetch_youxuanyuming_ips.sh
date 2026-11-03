#!/bin/bash
set -e

# Source the logging library
source "$(dirname "$0")/../../lib/logging.sh"

FETCH_URL="https://github.com/killbus/youxuanyuming/raw/refs/heads/data/ip.txt"
OUTPUT_FILE="/tmp/cloudflare-ips-v4.txt"

info "Fetching IPs from $FETCH_URL..."

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
TMP_FILE="$WORK_DIR/ip.txt"

if ! curl -sfL --max-time 30 "$FETCH_URL" -o "$TMP_FILE"; then
    fatal "Failed to fetch IPs from $FETCH_URL."
fi

# Drop Windows line endings and blank lines before appending
sed -e 's/\r$//' "$TMP_FILE" | grep -v '^[[:space:]]*$' > "$TMP_FILE.clean" || true

if [ ! -s "$TMP_FILE.clean" ]; then
    fatal "Fetched IP list from $FETCH_URL is empty."
fi

# Ensure the output file ends with a newline before appending
if [ -s "$OUTPUT_FILE" ] && [ "$(tail -c 1 "$OUTPUT_FILE" | od -An -t x1 | tr -d ' \n')" != "0a" ]; then
    info "Adding newline to $OUTPUT_FILE before appending."
    echo "" >> "$OUTPUT_FILE"
fi

cat "$TMP_FILE.clean" >> "$OUTPUT_FILE"

count=$(wc -l < "$TMP_FILE.clean")
total=$(wc -l < "$OUTPUT_FILE")
info "Successfully appended $count IPs from $FETCH_URL to $OUTPUT_FILE (total: $total lines)"
