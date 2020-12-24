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
    curl -H "Authorization: token $GIST_TOKEN" -X POST -d "${DESC}" "https://api.github.com/gists/$GIST_ID"

fi
