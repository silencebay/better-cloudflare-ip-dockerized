#!/bin/bash
set -e

# Source the logging library
source "$(dirname "$0")/../../lib/logging.sh"

# fallback_isp_dns.sh: last-resort fallback before publishing to gist.
# When upstream tasks produced no usable IP list (empty or missing output
# file), resolve well-known Cloudflare domains through the system resolver
# (inside the container this forwards to the host's ISP DNS) and write the
# answers as the IP list. Files that already have content are left
# untouched, so a partially-successful upstream run is never overwritten.
# ISP-resolved IPs are the nearest anycast POPs as seen by the ISP's
# recursive resolver: guaranteed reachable, but not speed-tested.

# FALLBACK_DOMAINS: comma-separated domains to resolve (default:
#   Cloudflare's own domains). Add your own CF-proxied domain to get the
#   edge IPs your real traffic would actually hit.
FALLBACK_DOMAINS=${FALLBACK_DOMAINS:-speed.cloudflare.com,www.cloudflare.com,one.one.one.one}
# FALLBACK_DNS_SERVER: explicit DNS server to query (default: empty = the
#   container resolver, which forwards to the host's ISP DNS).
FALLBACK_DNS_SERVER=${FALLBACK_DNS_SERVER:-}
# FALLBACK_V4_FILE / FALLBACK_V6_FILE: files to check and fill when empty.
FALLBACK_V4_FILE=${FALLBACK_V4_FILE:-${OUTPUT_DIR:-/data}/ips-v4.txt}
FALLBACK_V6_FILE=${FALLBACK_V6_FILE:-${OUTPUT_DIR:-/data}/ips-v6.txt}

IFS=',' read -ra DOMAIN_ARRAY <<< "$FALLBACK_DOMAINS"

# has_content FILE: true when the file exists and contains at least one
# non-blank line. A file of only whitespace/newlines counts as no data,
# same definition as fetch_youxuanyuming_ips.sh uses when cleaning input.
has_content() {
    [ -f "$1" ] && [ -n "$(sed -e 's/\r$//' "$1" | grep -v '^[[:space:]]*$' | head -n 1)" ]
}

v4_needed=false
v6_needed=false
if ! has_content "$FALLBACK_V4_FILE"; then
    v4_needed=true
    warning "IP list $FALLBACK_V4_FILE is empty or blank, fallback needed"
fi
if ! has_content "$FALLBACK_V6_FILE"; then
    v6_needed=true
    warning "IP list $FALLBACK_V6_FILE is empty or blank, fallback needed"
fi

if [ "$v4_needed" = false ] && [ "$v6_needed" = false ]; then
    info "IP lists already present, ISP DNS fallback not needed"
    exit 0
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
: > "$WORK_DIR/v4.txt"
: > "$WORK_DIR/v6.txt"

resolved_any=false
for domain in "${DOMAIN_ARRAY[@]}"; do
    domain=$(echo "$domain" | xargs)
    [ -n "$domain" ] || continue

    info "Resolving $domain via ISP DNS..."
    if ! answer=$(nslookup "$domain" $FALLBACK_DNS_SERVER 2>/dev/null); then
        warning "DNS lookup for $domain failed, skipping"
        continue
    fi
    resolved_any=true

    # busybox nslookup output differs by version:
    #   new (1.30+): answers are "Address: 1.1.1.1" (no index), preceded by a
    #     "(Non-)authoritative answer:" separator; the resolver header
    #     "Address: 10.1.1.1:53" sits BEFORE that separator and must be
    #     excluded (it is the DNS server itself, not an answer).
    #   old: answers are "Address 1: 1.1.1.1" (indexed, no separator line).
    # Strategy: from the separator line to EOF when one exists (new format),
    # otherwise the whole output (old format, where the indexed pattern
    # excludes the un-indexed header). Then keep "Address [N]: value" lines.
    # Split by family: dotted quad = IPv4, colon form = IPv6.
    addresses=$(echo "$answer" \
        | sed -n '/[Aa]uthoritative answer:/,$p' \
        | sed -n 's/^[[:space:]]*Address[[:space:]]*[0-9]*:[[:space:]]*//p' \
        | sed 's/[[:space:]].*$//')
    if [ -z "$addresses" ]; then
        addresses=$(echo "$answer" \
            | sed -n 's/^Address[[:space:]]*[0-9][0-9]*:[[:space:]]*//p' \
            | sed 's/[[:space:]].*$//')
    fi
    echo "$addresses" | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' >> "$WORK_DIR/v4.txt" || true
    echo "$addresses" | grep ':' | grep -E '^([0-9a-fA-F]*:)+[0-9a-fA-F:]*$' >> "$WORK_DIR/v6.txt" || true
done

if [ "$resolved_any" = false ]; then
    fatal "Failed to resolve any of: $FALLBACK_DOMAINS"
fi

sort -u -o "$WORK_DIR/v4.txt" "$WORK_DIR/v4.txt"
sort -u -o "$WORK_DIR/v6.txt" "$WORK_DIR/v6.txt"

needed=0
filled=0

if [ "$v4_needed" = true ]; then
    needed=$((needed + 1))
    count=$(grep -c . "$WORK_DIR/v4.txt" || true)
    if [ "$count" -gt 0 ]; then
        cp "$WORK_DIR/v4.txt" "$FALLBACK_V4_FILE"
        info "Filled $FALLBACK_V4_FILE with $count ISP-resolved IPv4 addresses"
        filled=$((filled + 1))
    else
        warning "No IPv4 addresses resolved via ISP DNS, $FALLBACK_V4_FILE left empty"
    fi
fi

if [ "$v6_needed" = true ]; then
    needed=$((needed + 1))
    count=$(grep -c . "$WORK_DIR/v6.txt" || true)
    if [ "$count" -gt 0 ]; then
        cp "$WORK_DIR/v6.txt" "$FALLBACK_V6_FILE"
        info "Filled $FALLBACK_V6_FILE with $count ISP-resolved IPv6 addresses"
        filled=$((filled + 1))
    else
        warning "No IPv6 addresses resolved via ISP DNS, $FALLBACK_V6_FILE left empty"
    fi
fi

# If nothing could be filled, fail so the task retry kicks in; transient DNS
# hiccups get another chance before gist reports "No valid files found".
if [ "$filled" -eq 0 ]; then
    fatal "Fallback failed: no IPs resolved from $FALLBACK_DOMAINS"
fi

info "ISP DNS fallback completed: filled $filled of $needed missing files"
