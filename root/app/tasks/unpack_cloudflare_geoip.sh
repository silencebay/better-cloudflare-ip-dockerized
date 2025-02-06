#!/bin/bash
set -e

# Source the logging library
source "$(dirname "$0")/../lib/logging.sh"

# Required environment variables and defaults
# CLOUDFLARE_GEOIP_URL: URL to download geoip.dat
# V2DAT_URL: URL to download v2dat tool (optional)
# GEOIP_CACHE_HOURS: Number of hours to cache geoip.dat (default: 24)
DEFAULT_V2DAT_URL="https://github.com/m0xbf/v2dat/releases/download/v20240712/v2dat_20240712_amd64"
V2DAT_URL="${V2DAT_URL:-$DEFAULT_V2DAT_URL}"
V2DAT_CACHE="/usr/local/bin/v2dat"
GEOIP_CACHE_HOURS="${GEOIP_CACHE_HOURS:-24}"
GEOIP_CACHE="/usr/local/share/cloudflare/geoip.dat"

# Output file paths
CLOUDFLARE_IPS_OUTPUT="/tmp/cloudflare-ips.txt"
CLOUDFLARE_IPV4_OUTPUT="/tmp/cloudflare-ips-v4.txt"
CLOUDFLARE_IPV6_OUTPUT="/tmp/cloudflare-ips-v6.txt"

# Validate required environment variables
if [ -z "$CLOUDFLARE_GEOIP_URL" ]; then
    fatal "CLOUDFLARE_GEOIP_URL is not set"
fi

# Create temp directory
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Set file paths
RULES_DIR="$WORK_DIR/rules"

# Download or use cached v2dat tool
if [ ! -x "$V2DAT_CACHE" ]; then
    info "Downloading v2dat tool..."
    if ! curl -L -o "$V2DAT_CACHE" "$V2DAT_URL"; then
        fatal "Failed to download v2dat tool"
    fi
    chmod +x "$V2DAT_CACHE"
else
    info "Using cached v2dat tool"
fi

# Check if we need to update geoip.dat cache
mkdir -p "$(dirname "$GEOIP_CACHE")"
need_download=true
if [ -f "$GEOIP_CACHE" ]; then
    # Get file age in hours
    file_age=$(($(date +%s) - $(stat -c %Y "$GEOIP_CACHE")))
    file_age_hours=$((file_age / 3600))
    
    if [ "$file_age_hours" -lt "$GEOIP_CACHE_HOURS" ]; then
        need_download=false
        info "Using cached geoip.dat (age: ${file_age_hours}h, max: ${GEOIP_CACHE_HOURS}h)"
    else
        info "Cache expired (age: ${file_age_hours}h, max: ${GEOIP_CACHE_HOURS}h)"
    fi
fi

# Download geoip.dat if needed
if [ "$need_download" = true ]; then
    info "Downloading geoip.dat..."
    if ! curl -L -o "$GEOIP_CACHE" "$CLOUDFLARE_GEOIP_URL"; then
        fatal "Failed to download geoip.dat"
    fi
fi

# Create output directory
mkdir -p "$RULES_DIR"

# Unpack geoip.dat
info "Unpacking geoip.dat..."
if ! "$V2DAT_CACHE" unpack geoip -o "$RULES_DIR" -f cloudflare "$GEOIP_CACHE"; then
    fatal "Failed to unpack geoip.dat"
fi

# Check if the output file exists
CLOUDFLARE_RULES="$RULES_DIR/geoip_cloudflare.txt"
if [ ! -f "$CLOUDFLARE_RULES" ]; then
    fatal "Cloudflare IP rules file not found after unpacking"
fi

# Split IPs by version and copy to final destinations
info "Separating IPv4 and IPv6 addresses..."

# Copy all IPs
cp "$CLOUDFLARE_RULES" "$CLOUDFLARE_IPS_OUTPUT"

# Extract IPv4 addresses (no colons)
grep -v ":" "$CLOUDFLARE_RULES" > "$CLOUDFLARE_IPV4_OUTPUT"

# Extract IPv6 addresses (contains colons)
grep ":" "$CLOUDFLARE_RULES" > "$CLOUDFLARE_IPV6_OUTPUT"

# Print stats
TOTAL_COUNT=$(wc -l < "$CLOUDFLARE_IPS_OUTPUT")
IPV4_COUNT=$(wc -l < "$CLOUDFLARE_IPV4_OUTPUT")
IPV6_COUNT=$(wc -l < "$CLOUDFLARE_IPV6_OUTPUT")

info "IP addresses extracted successfully:"
info "- Total IPs: $TOTAL_COUNT"
info "- IPv4 addresses: $IPV4_COUNT (saved to $CLOUDFLARE_IPV4_OUTPUT)"
info "- IPv6 addresses: $IPV6_COUNT (saved to $CLOUDFLARE_IPV6_OUTPUT)"

# Sample of IPs
info "Sample of IPv4 addresses:"
head -n 3 "$CLOUDFLARE_IPV4_OUTPUT"
info "Sample of IPv6 addresses:"
head -n 3 "$CLOUDFLARE_IPV6_OUTPUT"
