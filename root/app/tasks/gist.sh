#! /bin/bash

# Source the logging library
source "$(dirname "$0")/../lib/logging.sh"

# FILENAME=$1
FILENAME=/data/ip.txt

if [ ! -f "$FILENAME" ]; then
    fatal "File $FILENAME does not exist"
fi

CONTENT=$(sed -e 's/\r//' -e's/\t/\\t/g' -e 's/"/\\"/g' "${FILENAME}" | awk '{ printf($0 "\\n") }')
GIST_FILENAME=${GIST_FILENAME:-FILENAME}

# Validate required environment variables
for var in GIST_TOKEN GIST_ID; do
    if [ -z "${!var}" ]; then
        fatal "$var is not set"
    fi
done

read -r -d '' DESC <<EOF
{
  "files": {
    "${GIST_FILENAME}": {
      "content": "${CONTENT}"
    }
  }
}
EOF

info "Updating gist with content from $FILENAME"

# Use curl to send a POST request
status_code=$(curl -L \
    -H "Authorization: token $GIST_TOKEN" \
    -X PATCH \
    -d "${DESC}" \
    "https://api.github.com/gists/$GIST_ID" \
    -w "%{http_code}" \
    -o /dev/null)

if [ "$status_code" -eq 200 ]; then
    info "Gist updated successfully!"
else
    error "Gist update failed. Status code: $status_code"
    # You can choose to print error details here, but be mindful that the body might be large.
    # curl -H "Authorization: token $GIST_TOKEN" -X PATCH -d "${DESC}" "https://api.github.com/gists/$GIST_ID"
    exit 1
fi
