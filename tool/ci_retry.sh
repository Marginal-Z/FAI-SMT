#!/usr/bin/env bash
# Retry transient dependency downloads without hiding compilation failures.
set -u -o pipefail
log=$(mktemp)
trap 'rm -f "$log"' EXIT
for attempt in 1 2 3; do
  "$@" 2>&1 | tee "$log"
  result=$?
  if [ "$result" -eq 0 ]; then exit 0; fi
  if [ "$attempt" -eq 3 ] || ! grep -Eqi '(504|502|503|429|download.*fail|fail.*download|error.*download|could not (GET|HEAD)|timed? ?out|SocketException|Connection reset)' "$log"; then
    exit "$result"
  fi
  echo "::warning::Dependency download failed; retrying build ($attempt/3)."
  sleep "${CI_DOWNLOAD_RETRY_DELAY:-15}"
done
