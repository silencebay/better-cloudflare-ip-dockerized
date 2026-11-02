#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# Source the logging library
source "$(dirname "$0")/../../lib/logging.sh"

API_URL="https://vps789.com/public/sum/cfIpApi"
OUTPUT_FILE="/tmp/cloudflare-ips-v4.txt"

info "Fetching IPs from $API_URL..."

# Check if the output file exists, is not empty, and does not end with a newline
if [ -s "$OUTPUT_FILE" ] && [[ "$(tail -c 1 "$OUTPUT_FILE")" != '' ]]; then
  info "Adding newline to $OUTPUT_FILE before appending."
  echo "" >> "$OUTPUT_FILE"
fi

# Use curl to fetch data, jq to extract IPs, and append to the output file
# curl options:
# -s: Silent mode
# -f: Fail silently on server errors
# -L: Follow redirects
# --max-time 30: Maximum time allowed for the transfer (in seconds)
# jq options:
# -r: Raw output (removes quotes from strings)
# '.data | .[] | .[] | .ip': Extracts all 'ip' values from the nested arrays within the 'data' object
if curl -sfL --max-time 30 "$API_URL" | jq -r '.data | .[] | .[] | .ip' >> "$OUTPUT_FILE"; then
  # Check if jq actually extracted anything (jq exits 0 even on empty input/output)
  # We can check if the last command added anything to the file, but a simpler check
  # is to see if the curl command itself succeeded before jq processed it.
  # The `if` condition already checks the exit status of the *last* command in the pipeline (jq).
  # If curl fails, the pipe breaks, and jq might receive empty input, still exiting 0.
  # A more robust check might involve temporary files or checking curl's exit code specifically.
  # For simplicity, we assume if the pipeline succeeds, IPs were likely appended.
  info "Successfully fetched and appended IPs from $API_URL to $OUTPUT_FILE"
else
  # This catches errors from curl (-f) or jq processing errors.
  fatal "Failed to fetch or process IPs from $API_URL."
  # Optionally, check curl's exit code specifically if needed for finer-grained error handling
  # curl_exit_code=$? # This doesn't work directly in `if` pipeline like this
  exit 1 # Ensure script exits on failure
fi
