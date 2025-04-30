#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <SQS_QUEUE_URL> <URL> <output-filename.mkv> [s3-key-prefix]" >&2
  exit 1
fi

QUEUE_URL="$1"
URL="$2"
FILENAME="${3:-$(basename "$URL").mkv}"
PREFIX="${4:-recordings/$(date -u +%Y/%m/%d/)/}"

# generate a UUID for grouping & deduplication
if command -v uuidgen &>/dev/null; then
  JOB_ID=$(uuidgen)
else
  JOB_ID=$(cat /proc/sys/kernel/random/uuid)
fi

BODY=$(jq -nc \
  --arg jobId    "$JOB_ID" \
  --arg url      "$URL" \
  --arg filename "$FILENAME" \
  --arg s3Key    "${PREFIX}${FILENAME}" \
  '{jobId: $jobId, url: $url, filename: $filename, s3Key: $s3Key}')

# if AWS_ENDPOINT_URL is set, include it
if [[ -n "${AWS_ENDPOINT_URL:-}" ]]; then
  ENDPOINT_ARG="--endpoint-url $AWS_ENDPOINT_URL"
else
  ENDPOINT_ARG=""
fi

echo "Enqueuing job $JOB_ID..."
aws sqs send-message \
  $ENDPOINT_ARG \
  --queue-url "$QUEUE_URL" \
  --message-body "$BODY" \
  --message-group-id         "$JOB_ID" \
  --message-deduplication-id "$JOB_ID"

echo "✅ Job $JOB_ID submitted."
