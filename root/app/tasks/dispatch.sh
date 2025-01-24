#!/bin/bash

# Exit on error
set -e

# Function for logging
log() {
    echo "[$(date)] [dispatch] $1"
}

# Validate required environment variables
for var in DISPATCH_TOKEN DISPATCH_OWNER DISPATCH_REPO DISPATCH_WORKFLOW DISPATCH_REF; do
    if [ -z "${!var}" ]; then
        log "Error: $var is not set"
        exit 1
    fi
done

# Use provided inputs JSON or empty object
INPUTS_JSON="${DISPATCH_INPUTS:-{}}"

# Validate JSON format
if ! echo "$INPUTS_JSON" | jq empty 2>/dev/null; then
    log "Error: DISPATCH_INPUTS is not valid JSON"
    exit 1
fi

# Construct the request body using jq
REQUEST_BODY=$(jq -n \
    --arg ref "$DISPATCH_REF" \
    --argjson inputs "$INPUTS_JSON" \
    '{ref: $ref, inputs: $inputs}')

# GitHub API request to trigger workflow
log "Triggering workflow dispatch with payload: $REQUEST_BODY"

response=$(curl -L \
    -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $DISPATCH_TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "Content-Type: application/json" \
    "https://api.github.com/repos/${DISPATCH_OWNER}/${DISPATCH_REPO}/actions/workflows/${DISPATCH_WORKFLOW}/dispatches" \
    -d "$REQUEST_BODY" \
    -w "\n%{http_code}" \
    -s)

status_code=$(echo "$response" | tail -n1)
response_body=$(echo "$response" | sed '$d')

if [ "$status_code" -eq 204 ]; then
    log "Workflow dispatch triggered successfully!"
else
    log "Workflow dispatch failed. Status code: $status_code"
    [ -n "$response_body" ] && log "Response: $response_body"
    exit 1
fi 