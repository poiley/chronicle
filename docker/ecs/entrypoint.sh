#!/usr/bin/env bash
set -euo pipefail

# If AWS_ENDPOINT_URL is defined (LocalStack), include it on every aws call
# Additionally, set up AWS credentials for localstack run
if [[ -n "${AWS_ENDPOINT_URL:-}" ]]; then
  export AWS_ACCESS_KEY_ID="test"
  export AWS_SECRET_ACCESS_KEY="test"
  export AWS_REGION="us-east-1"
  AWS_CLI="aws --endpoint-url $AWS_ENDPOINT_URL --region $AWS_REGION"
else
  AWS_CLI="aws"
fi

# Required env from Lambda/ECS:
#   JOB_ID     — from SQS body
#   DDB_TABLE  — DynamoDB table name
#   S3_BUCKET  — target S3 bucket
#   S3_KEY     — target S3 key prefix
#   TTL_DAYS   — record TTL in days
URL="$1"
OUTFILE="$2"
TARGET="/downloads/${OUTFILE%.*}.mkv"
LOGFILE="/tmp/${JOB_ID}.log"

TIMESTAMP() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# ddb_update <STATUS> <EXPR_SUFFIX> <VALS_FRAGMENT>
# e.g. ddb_update RECORDING ", foo = :f"  '":f":{"S":"bar"}'
ddb_update(){
  local status="$1"
  local expr_suffix="$2"
  local vals_frag="$3"

  # Build JSON for --expression-attribute-values
  local json="{\":s\":{\"S\":\"$status\"}"
  if [[ -n "$vals_frag" ]]; then
    json+=",${vals_frag}"
  fi
  json+="}"

  # Replace any reserved words with expression attribute names
  # Convert "ttl = :ttl" to "#ttl = :ttl" in expr_suffix
  expr_suffix="${expr_suffix//ttl = /#ttl = }"
  
  # Add ttl to attribute names if needed
  local attr_names='{"#s":"status"}'
  if [[ "$expr_suffix" == *"#ttl"* ]]; then
    attr_names='{"#s":"status","#ttl":"ttl"}'
  fi

  $AWS_CLI dynamodb update-item \
    --table-name "$DDB_TABLE" \
    --key "{\"jobId\":{\"S\":\"$JOB_ID\"}}" \
    --update-expression "SET #s = :s${expr_suffix}" \
    --expression-attribute-names "$attr_names" \
    --expression-attribute-values "$json"
}

# 1) RECORDING + set TTL
ttl_epoch=$(( $(date +%s) + TTL_DAYS*86400 ))
ddb_update RECORDING \
  ", recordingAt = :ra, ttl = :ttl" \
  '":ra":{"S":"'"$(TIMESTAMP)"'"},":ttl":{"N":"'"$ttl_epoch"'"}'

# 2) start download in background
yt-dlp \
  --live-from-start \
  --hls-prefer-ffmpeg \
  --hls-use-mpegts \
  -f bestvideo+bestaudio \
  --merge-output-format mkv \
  -o "$TARGET" \
  "$URL" 2>>"$LOGFILE" &
dl_pid=$!

# 3) heartbeat every 60s
while kill -0 "$dl_pid" 2>/dev/null; do
  now=$(TIMESTAMP)
  size=$(stat -c%s "$TARGET" 2>/dev/null || echo 0)
  $AWS_CLI dynamodb update-item \
    --table-name "$DDB_TABLE" \
    --key "{\"jobId\":{\"S\":\"$JOB_ID\"}}" \
    --update-expression "SET lastHeartbeat = :hb, bytesDownloaded = :bd" \
    --expression-attribute-values "{\":hb\":{\"S\":\"$now\"},\":bd\":{\"N\":\"$size\"}}"
  sleep 60
done

wait "$dl_pid"
exit_code=$?

if [ $exit_code -ne 0 ]; then
  # 4) FAILED
  err=$(tail -c 2048 "$LOGFILE" | sed 's/"/\\"/g')
  $AWS_CLI dynamodb update-item \
    --table-name "$DDB_TABLE" \
    --key "{\"jobId\":{\"S\":\"$JOB_ID\"}}" \
    --update-expression "SET #s = :s, finishedAt = :ft, errorDetail = :err" \
    --expression-attribute-names '{"#s":"status"}' \
    --expression-attribute-values "{\":s\":{\"S\":\"FAILED\"},\":ft\":{\"S\":\"$(TIMESTAMP)\"},\":err\":{\"S\":\"$err\"}}"
  exit $exit_code
fi

# 5) UPLOADING
ddb_update UPLOADING \
  ", uploadingAt = :ua" \
  '":ua":{"S":"'"$(TIMESTAMP)"'"}'

$AWS_CLI s3 cp "$TARGET" "s3://$S3_BUCKET/$S3_KEY/" 2>>"$LOGFILE"

# 6) COMPLETED
ddb_update COMPLETED \
  ", finishedAt = :ft" \
  '":ft":{"S":"'"$(TIMESTAMP)"'"}'
