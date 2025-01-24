#! /bin/bash

FILENAME=$1

if [ -f $FILENAME ]; then
    CONTENT=$(sed -e 's/\r//' -e's/\t/\\t/g' -e 's/"/\\"/g' "${FILENAME}" | awk '{ printf($0 "\\n") }')
    GIST_FILENAME=${GIST_FILENAME:-FILENAME}

    read -r -d '' DESC <<EOF
  {
    "files": {
      "${GIST_FILENAME}": {
        "content": "${CONTENT}"
      }
    }
  }
EOF

    # 3. Use curl to send a POST request
    status_code=$(curl -L -H "Authorization: token $GIST_TOKEN" -X PATCH -d "${DESC}" "https://api.github.com/gists/$GIST_ID" -w "%{http_code}" -o /dev/null)

    if [ "$status_code" -eq 200 ]; then
      echo "Gist updated successfully!"
    else
      echo "Gist update failed. Status code: $status_code"
      # You can choose to print error details here, but be mindful that the body might be large.
      # curl -H "Authorization: token $GIST_TOKEN" -X PATCH -d "${DESC}" "https://api.github.com/gists/$GIST_ID"
    fi   

fi
