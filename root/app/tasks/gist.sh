#! /bin/bash

# Source the logging library
source "$(dirname "$0")/../lib/logging.sh"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    fatal "jq is required but not installed"
fi

# Default to /data/ip.txt if GIST_INPUT_FILES not set
GIST_INPUT_FILES=${GIST_INPUT_FILES:-/data/ip.txt}

# Convert comma-separated strings to arrays
IFS=',' read -ra FILE_ARRAY <<< "$GIST_INPUT_FILES"
IFS=',' read -ra FILENAME_ARRAY <<< "${GIST_FILENAME:-}"

# Initialize empty JSON object
json_content="{}"

# First process individual files
has_valid_files=false
for index in "${!FILE_ARRAY[@]}"; do
    FILENAME=$(echo "${FILE_ARRAY[$index]}" | xargs)
    
    if [ ! -f "$FILENAME" ]; then
        warning "File $FILENAME does not exist, skipping..."
        continue
    fi

    # Check if file is empty
    if [ ! -s "$FILENAME" ]; then
        warning "File $FILENAME is empty, skipping..."
        continue
    fi

    has_valid_files=true
    
    # Get the base filename without the path
    DEFAULT_GIST_FILENAME=$(basename "$FILENAME")
    
    # Use custom filename from GIST_FILENAME array if available and not empty
    CUSTOM_FILENAME="${FILENAME_ARRAY[$index]:-}"
    if [ -n "$CUSTOM_FILENAME" ] && [ "$CUSTOM_FILENAME" != " " ]; then
        GIST_FILENAME="$CUSTOM_FILENAME"
    else
        GIST_FILENAME="$DEFAULT_GIST_FILENAME"
    fi
    
    # If there are duplicate filenames, append index to make them unique
    if echo "$json_content" | jq -e ".files.\"$GIST_FILENAME\"" >/dev/null; then
        GIST_FILENAME="${GIST_FILENAME%.*}_${index}.${GIST_FILENAME##*.}"
    fi

    # Use jq to handle content formatting and JSON structure, with process substitution
    # to handle Windows-style line endings
    json_content=$(echo "$json_content" | jq --arg filename "$GIST_FILENAME" --rawfile content \
        <(sed -e 's/\r//' "$FILENAME") \
        '.files[$filename] = {"content": $content}')
done

# Check if we processed any files
if [ "$has_valid_files" = false ]; then
    fatal "No valid files found in: $GIST_INPUT_FILES"
fi

# If GIST_MERGE_FILENAME is set, create a merged file
if [ -n "$GIST_MERGE_FILENAME" ]; then
    # Use process substitution to create merged content
    json_content=$(echo "$json_content" | jq --arg filename "$GIST_MERGE_FILENAME" --rawfile content \
        <(for file in "${FILE_ARRAY[@]}"; do
            file=$(echo "$file" | xargs)
            sed -e 's/\r//' "$file"
        done) \
        '.files[$filename] = {"content": $content}')
fi

# Validate required environment variables
for var in GIST_TOKEN GIST_ID; do
    if [ -z "${!var}" ]; then
        fatal "$var is not set"
    fi
done

info "Updating gist with content from: $GIST_INPUT_FILES"

# Use curl to send a POST request with heredoc
response=$(curl -L \
    -X PATCH \
    -H "Authorization: token $GIST_TOKEN" \
    -H "Content-Type: application/json" \
    -w "\n%{http_code}" \
    -s \
    "https://api.github.com/gists/$GIST_ID" \
    --data-binary @- << EOF
$json_content
EOF
)

status_code=$(echo "$response" | tail -n1)
response_body=$(echo "$response" | sed '$d')

if [ "$status_code" -eq 200 ]; then
    info "Gist updated successfully!"
else
    error "Gist update failed. Status code: $status_code"
    [ -n "$response_body" ] && error "Response: $response_body"
    exit 1
fi
