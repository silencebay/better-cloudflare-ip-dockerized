#!/bin/bash

# Exit on error
set -e

# Source the logging library
source "$(dirname "$0")/../lib/logging.sh"

# Validate required environment variables
for var in DISPATCH_TOKEN DISPATCH_OWNER DISPATCH_REPO DISPATCH_WORKFLOW DISPATCH_REF; do
    if [ -z "${!var}" ]; then
        fatal "$var is not set"
    fi
done

# Use provided inputs JSON or empty object
INPUTS_JSON="${DISPATCH_INPUTS:-"{}"}"

# Validate JSON format
if ! echo "$INPUTS_JSON" | jq empty 2>/dev/null; then
    fatal "DISPATCH_INPUTS is not valid JSON"
fi

# Construct request body and send using heredoc
REQUEST_BODY=$(jq -n \
    --arg ref "$DISPATCH_REF" \
    --arg inputs "$INPUTS_JSON" \
    '{ref: $ref, inputs: ($inputs | fromjson | .)}')

info "Triggering workflow dispatch with payload: $REQUEST_BODY"

response=$(curl -L \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $DISPATCH_TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/${DISPATCH_OWNER}/${DISPATCH_REPO}/actions/workflows/${DISPATCH_WORKFLOW}/dispatches" \
    -w "\n%{http_code}" \
    -s \
    --data-binary @- << EOF
$REQUEST_BODY
EOF
)

status_code=$(echo "$response" | tail -n1)
response_body=$(echo "$response" | sed '$d')

if [ "$status_code" -eq 204 ]; then
    info "Workflow dispatch triggered successfully!"
else
    error "Workflow dispatch failed. Status code: $status_code"
    [ -n "$response_body" ] && error "Response: $response_body"
    exit 1
fi 