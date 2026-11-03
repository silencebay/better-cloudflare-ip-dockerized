#!/bin/bash
set -e

# Source the logging library
source "$(dirname "$0")/../../lib/logging.sh"

# Same configuration as test.sh (this task runs between `test` and `gist`)
RESULT_FILE=${RESULT_FILE:-/tmp/result.csv}
OUTPUT_DIR=${OUTPUT_DIR:-/data}
# By default, keep the same output size as test.sh (TOP_N); override it
# independently with FILTER_OUTPUT_LIMIT if needed.
OUTPUT_LIMIT=${FILTER_OUTPUT_LIMIT:-${TOP_N:-10}}

# Probe configuration
# FILTER_PROBE_URL: fixed test URL. Each candidate IP is probed by resolving the
#   URL's host to that IP (curl --resolve), so the request is answered by
#   that specific Cloudflare edge. Point this at your own domain
#   (https://your-domain/...) to test the real origin path, or keep the
#   default for a plain edge-aliveness check.
# FILTER_ACCEPT_STATUS: allowlist of HTTP status codes that count as "pass".
#   Supports single codes (200), ranges (200-299), and comma-separated
#   combinations (200,301 or 200-299,301). Use "any" to accept any HTTP
#   status code (still requires a successful HTTP response). 000 (connection
#   failure/timeout) is not an HTTP status code and always fails. Redirects
#   are NOT followed (no -L), so a 301 means the edge returned 301 directly.
# FILTER_ALLOW_EMPTY: when no IP matches FILTER_ACCEPT_STATUS, write an empty
#   result.csv instead of keeping the previous one (default: false).
FILTER_PROBE_URL=${FILTER_PROBE_URL:-https://speed.cloudflare.com}
FILTER_ACCEPT_STATUS=${FILTER_ACCEPT_STATUS:-200}
FILTER_TIMEOUT=${FILTER_TIMEOUT:-5}
FILTER_CONCURRENCY=${FILTER_CONCURRENCY:-20}
FILTER_PROBE_ROWS=${FILTER_PROBE_ROWS:-200}
FILTER_ALLOW_EMPTY=${FILTER_ALLOW_EMPTY:-false}

# The result file must exist and contain data
if [ ! -s "$RESULT_FILE" ]; then
    warning "Result file $RESULT_FILE not found or empty, nothing to filter"
    exit 0
fi

# Status allowlist: parse FILTER_ACCEPT_STATUS into codes and ranges
ACCEPT_ANY=false
ACCEPT_CODES=()
ACCEPT_RANGES=()

parse_accept_status() {
    local raw="$1"
    if [ -z "$raw" ]; then
        fatal "FILTER_ACCEPT_STATUS is set but empty; use 200, 200-299, 200,301, or any"
    fi
    if [ "${raw,,}" = "any" ]; then
        ACCEPT_ANY=true
        return
    fi
    local IFS=','
    read -ra TOKENS <<< "$raw"
    local token
    for token in "${TOKENS[@]}"; do
        token="${token//[[:space:]]/}"
        if [ -z "$token" ]; then
            fatal "FILTER_ACCEPT_STATUS contains an empty item: '$raw'"
        fi
        if [[ "$token" =~ ^([0-9]{3})-([0-9]{3})$ ]]; then
            local lo=${BASH_REMATCH[1]} hi=${BASH_REMATCH[2]}
            if [ "$lo" -eq 0 ] || [ "$hi" -eq 0 ]; then
                fatal "FILTER_ACCEPT_STATUS: 000 is not a valid HTTP status; remove it from '$raw'"
            fi
            if [ "$lo" -gt "$hi" ]; then
                fatal "FILTER_ACCEPT_STATUS range '$token' has lo > hi"
            fi
            ACCEPT_RANGES+=("$lo $hi")
        elif [[ "$token" =~ ^[0-9]{3}$ ]]; then
            if [ "$token" -eq 0 ]; then
                fatal "FILTER_ACCEPT_STATUS: 000 is not a valid HTTP status; remove it from '$raw'"
            fi
            ACCEPT_CODES+=("$token")
        else
            fatal "FILTER_ACCEPT_STATUS: invalid item '$token' in '$raw' (expected NNN or NNN-NNN)"
        fi
    done
    if [ ${#ACCEPT_CODES[@]} -eq 0 ] && [ ${#ACCEPT_RANGES[@]} -eq 0 ]; then
        fatal "FILTER_ACCEPT_STATUS contains no valid status codes: '$raw'"
    fi
}

status_allowed() {
    local code=$1
    [[ "$code" =~ ^[0-9]{3}$ ]] || return 1
    [ "$code" -eq 0 ] && return 1
    if [ "$ACCEPT_ANY" = "true" ]; then
        return 0
    fi
    local c
    for c in "${ACCEPT_CODES[@]}"; do
        if [ "$code" -eq "$c" ]; then
            return 0
        fi
    done
    local pair lo hi
    for pair in "${ACCEPT_RANGES[@]}"; do
        read -r lo hi <<< "$pair"
        if [ "$code" -ge "$lo" ] && [ "$code" -le "$hi" ]; then
            return 0
        fi
    done
    return 1
}

parse_accept_status "$FILTER_ACCEPT_STATUS"

require_integer_in_range() {
    local name=$1 value=$2 min=$3 max=$4
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        fatal "$name must be a non-negative integer (got: $value)"
    fi
    if [ "$value" -lt "$min" ] || [ "$value" -gt "$max" ]; then
        fatal "$name must be between $min and $max (got: $value)"
    fi
}

require_integer_in_range FILTER_TIMEOUT "$FILTER_TIMEOUT" 1 86400
require_integer_in_range FILTER_CONCURRENCY "$FILTER_CONCURRENCY" 1 1024
require_integer_in_range FILTER_PROBE_ROWS "$FILTER_PROBE_ROWS" 0 100000
require_integer_in_range OUTPUT_LIMIT "$OUTPUT_LIMIT" 1 100000

if [ "${FILTER_ALLOW_EMPTY,,}" = "true" ] || [ "${FILTER_ALLOW_EMPTY,,}" = "1" ]; then
    FILTER_ALLOW_EMPTY=true
elif [ "${FILTER_ALLOW_EMPTY,,}" = "false" ] || [ "${FILTER_ALLOW_EMPTY,,}" = "0" ]; then
    FILTER_ALLOW_EMPTY=false
else
    fatal "FILTER_ALLOW_EMPTY must be true or false (got: $FILTER_ALLOW_EMPTY)"
fi

mkdir -p "$OUTPUT_DIR"

# Derive host/port from the probe URL; fail fast on malformed values
if [[ "$FILTER_PROBE_URL" == http://* ]]; then
    FILTER_PORT=80
    URL_BODY=${FILTER_PROBE_URL#http://}
elif [[ "$FILTER_PROBE_URL" == https://* ]]; then
    FILTER_PORT=443
    URL_BODY=${FILTER_PROBE_URL#https://}
else
    fatal "FILTER_PROBE_URL must start with http:// or https:// (got: $FILTER_PROBE_URL)"
fi
URL_BODY=${URL_BODY%%/*}
if [[ "$URL_BODY" == *@* ]]; then
    URL_BODY=${URL_BODY##*@}
fi
if [ -z "$URL_BODY" ]; then
    fatal "FILTER_PROBE_URL has no host (got: $FILTER_PROBE_URL)"
fi
if [[ "$URL_BODY" == *:* ]]; then
    FILTER_PORT=${URL_BODY##*:}
    URL_BODY=${URL_BODY%%:*}
    if [[ "$FILTER_PORT" =~ ^[0-9]+$ ]] && [ "$FILTER_PORT" -ge 1 ] && [ "$FILTER_PORT" -le 65535 ]; then
        :
    else
        fatal "FILTER_PROBE_URL has an invalid port (got: $FILTER_PROBE_URL)"
    fi
fi
FILTER_HOST=$URL_BODY

# Candidate IPs in result.csv order (descending download speed)
mapfile -t ALL_IPS < <(tail -n +2 "$RESULT_FILE" | awk -F, '{print $1}')
total=${#ALL_IPS[@]}
if [ "$total" -eq 0 ]; then
    warning "No candidate IPs in $RESULT_FILE"
    exit 0
fi

probe_count=$total
if [ "$FILTER_PROBE_ROWS" -gt 0 ] && [ "$total" -gt "$FILTER_PROBE_ROWS" ]; then
    probe_count=$FILTER_PROBE_ROWS
    info "Probing first $probe_count of $total IPs (result.csv is sorted by speed desc)"
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
STATUS_FILE="$WORK_DIR/status.txt"
: > "$STATUS_FILE"

info "Probing candidate IPs against $FILTER_PROBE_URL (timeout ${FILTER_TIMEOUT}s, concurrency $FILTER_CONCURRENCY)..."

probe() {
    local ip=$1
    local code
    # --resolve pins the URL's host to this IP; 000 = connection failure/timeout
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time "$FILTER_TIMEOUT" \
        --resolve "$FILTER_HOST:$FILTER_PORT:$ip" "$FILTER_PROBE_URL" 2>/dev/null) || code=000
    printf '%s %s\n' "$ip" "$code" >> "$STATUS_FILE"
    return 0
}

# Probe with a bounded number of concurrent jobs
running=0
for ((i = 0; i < probe_count; i++)); do
    probe "${ALL_IPS[i]}" &
    running=$((running + 1))
    if ((running >= FILTER_CONCURRENCY)); then
        wait -n
        running=$((running - 1))
    fi
done
wait

# Split probed IPs by status allowlist
: > "$WORK_DIR/good_ips.txt"
while read -r ip code; do
    [ -n "$ip" ] || continue
    if status_allowed "$code"; then
        echo "$ip" >> "$WORK_DIR/good_ips.txt"
    fi
done < "$STATUS_FILE"
good_count=$(wc -l < "$WORK_DIR/good_ips.txt")
dropped_count=$((probe_count - good_count))

info "Probe results: $probe_count probed, $good_count kept, $dropped_count dropped"
status_summary=$(awk '{print $2}' "$STATUS_FILE" | sort | uniq -c | sort -rn | awk '{printf "%s(%s) ", $2, $1}')
info "Status distribution: $status_summary"

# If everything failed, keep the previous results rather than publishing an
# empty list (stale but working beats broken) unless explicitly overridden.
if [ "$good_count" -eq 0 ]; then
    warning "No IP matched FILTER_ACCEPT_STATUS against $FILTER_PROBE_URL"
    if [ "$FILTER_ALLOW_EMPTY" != "true" ]; then
        warning "Keeping previous results (set FILTER_ALLOW_EMPTY=true to write empty)"
        exit 0
    fi
fi

# Rebuild result.csv keeping only the IPs that passed the status allowlist (original order)
tail -n +2 "$RESULT_FILE" > "$WORK_DIR/rows.csv"
{
    head -n 1 "$RESULT_FILE"
    awk -F, 'NR==FNR { good[$1] = 1; next } ($1 in good)' "$WORK_DIR/good_ips.txt" "$WORK_DIR/rows.csv"
} > "$WORK_DIR/result.new"
mv "$WORK_DIR/result.new" "$RESULT_FILE"

# Re-derive the IP lists from the filtered results (same logic as test.sh)
best_ips=$(tail -n +2 "$RESULT_FILE" | head -n "$OUTPUT_LIMIT" | awk -F, '{print $1}')
if [ -z "$best_ips" ]; then
    warning "No IPs left in result file after filtering"
fi

echo "$best_ips" > "$OUTPUT_DIR/ips.txt"
echo "$best_ips" | grep -v ":" > "$OUTPUT_DIR/ips-v4.txt" || true
echo "$best_ips" | grep ":" > "$OUTPUT_DIR/ips-v6.txt" || true

ipv4_count=$(wc -l < "$OUTPUT_DIR/ips-v4.txt")
ipv6_count=$(wc -l < "$OUTPUT_DIR/ips-v6.txt")

info "Regenerated IP lists from filtered results:"
info "- Total IPs: $(echo "$best_ips" | wc -l) (saved to $OUTPUT_DIR/ips.txt)"
info "- IPv4 addresses: $ipv4_count (saved to $OUTPUT_DIR/ips-v4.txt)"
info "- IPv6 addresses: $ipv6_count (saved to $OUTPUT_DIR/ips-v6.txt)"
