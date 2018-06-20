#!/bin/bash

# This script verifies that no user-provided links in agarrharr/awesome-cli-apps
# broken. It does so by making a HTTP request to each website and looking at
# the status code of the response.
#
# If the request responds with 5xx the script terminates with a status code of
# 1, meaning a link is broken. 3xx and 4xx responses are treated as warnings
# and are simply logged, because they do not guarantee that there is something
# wrong with the requested website. The status code 000 is also treated as a
# warning because the status code alone does not specify where the problem
# lies, only that there is a problem, read more here: https://tinyurl.com/superuser-status-code-000
#
### Dependencies
# - ggrep (GNU flavored grep, comes with `brew install coreutils`)
# - curl
# - GNU parallel
#
### Usage
#
#  /bin/bash ./verify-links.sh
#
### Improvements
# - Use grep instead of ggrep to avoid potential additional dependency
#
# Author: http://github.com/simeg
# License: MIT
#

readonly SOURCE_FILE_URL="https://raw.githubusercontent.com/agarrharr/awesome-cli-apps/master/readme.md"
readonly JOBS_COUNT=100

readonly REGEX_URLS='(\((http(s*)\:\/\/.+)\))(\s-\s)'

echo "Fetching source file.."
readonly URL_STRING=$(curl --silent "${SOURCE_FILE_URL}" | ggrep -oP "${REGEX_URLS}")
echo "OK!"

echo "Parsing URLs from file..."
RAW_URLS_FILE=$(mktemp)
for URL in $URL_STRING; do
  if [ "$URL" != "-" ]; then
    echo "${URL:1:${#URL}-2}" >> "$RAW_URLS_FILE"
  fi
done
echo "OK!"

curl_for_status_code() {
  local url="$1"
  local status_code=

  status_code=$(
    curl "$url" \
    --silent \
    --head \
    --max-time 5 \
    -L \
    --write-out "%{http_code}" \
    --output /dev/null
  )
  printf "%s\\t%d\\n" "$url" "$status_code"
}

# Make function available for parallel
export -f curl_for_status_code

printf "Found [ %s ] URLs, cURLing them...\\n" "$(wc -l < "$RAW_URLS_FILE")"

URLS_WITH_STATUSES_FILE=$(mktemp)
parallel --jobs $JOBS_COUNT curl_for_status_code < $RAW_URLS_FILE >> $URLS_WITH_STATUSES_FILE

cat $URLS_WITH_STATUSES_FILE | while read RESULT
do
  URL=$(echo "$RESULT" | cut -f1)
  STATUS_CODE=$(echo "$RESULT" | cut -f2)
  FIRST_DIGIT=${STATUS_CODE:0:1}

  if [ "${FIRST_DIGIT}" == "2" ]; then
    echo OK!
  elif [ "${FIRST_DIGIT}" == "4" ]; then
    printf "WARNING: URL [ %s ] responded with status code [ %d ], continuing..\\n" "$URL" "$STATUS_CODE"
  elif [ "${FIRST_DIGIT}" == "5" ]; then
    printf "ERROR: URL [ %s ] responded with status code [ %d ], aborting!\\n" "$URL" "$STATUS_CODE"
    exit 1
  elif [ "${STATUS_CODE}" == "000" ]; then
    printf "ERROR: URL [ %s ] responded with status code [ %d ], aborting!\\n" "$URL" "$STATUS_CODE"
    exit 1
  else
    printf "UNKNOWN STATUS CODE: URL [ %s ] responded with status code [ %d ], continuing..\\n" "$URL" "$STATUS_CODE"
  fi
done
