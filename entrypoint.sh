#!/usr/bin/env bash
set -euo pipefail

# Required environment:
#   JOB_ID       — from Lambda override
#   DDB_TABLE    — from task definition
#   S3_BUCKET    — from Lambda override
#   S3_KEY       — from Lambda override
#   TTL_DAYS     — from task definition

URL="$1"
OUTFILE="$2"
TARGET="/downloads/${OUTFILE%.*}.mkv"

TIMESTAMP(){ date -u +%Y-%m-%dT%H:%M:%SZ; }

# Helper to update status in DynamoDB
ddb_update(){
  local status="$1" updates="${2:-}"
  aws dynamodb update-item \
    --table-name "$DDB_TABLE" \
    --key "{\"jobId\":{\"S\":\"$JOB_ID\"}}" \
    --update-expression "SET #s = :s${updates}" \
    --expression-attribute-names '{"#s":"status"}' \
    --expression-attribute-values "{\"\":{\"S\":\"$status\"}${3:-}}"
}

LOGFILE="/tmp/${JOB_ID}.log"

# 1) RECORDING
# compute TTL epoch = now + TTL_DAYS*24*3600
ttl_epoch=$(( $(date +%s) + TTL_DAYS*86400 ))
ddb_update RECORDING ", recordingAt = :ra, ttl = :ttl" \
  ":ra\":{\"S\":\"$(TIMESTAMP)\"},\":ttl\":{\"N\":\"$ttl_epoch\"}"

# 2) Start yt-dlp and capture logs
yt-dlp \
  --live-from-start \
  --hls-prefer-ffmpeg \
  --hls-use-mpegts \
  -f bestvideo+bestaudio \
  --merge-output-format mkv \
  -o "$TARGET" \
  "$URL" 2>>"$LOGFILE" &

dl_pid=$!

# 3) Heartbeats every 60s
while kill -0 "$dl_pid" 2>/dev/null; do
  now=$(TIMESTAMP)
  size=$(stat -c%s "$TARGET" 2>/dev/null || echo 0)
  aws dynamodb update-item \
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
  aws dynamodb update-item \
    --table-name "$DDB_TABLE" \
    --key "{\"jobId\":{\"S\":\"$JOB_ID\"}}" \
    --update-expression "SET #s = :s, finishedAt = :ft, errorDetail = :err" \
    --expression-attribute-names '{"#s":"status"}' \
    --expression-attribute-values "{\":s\":{\"S\":\"FAILED\"},\":ft\":{\"S\":\"$(TIMESTAMP)\"},\":err\":{\"S\":\"$err\"}}"
  exit $exit_code
fi

# 5) UPLOADING
ddb_update UPLOADING ", uploadingAt = :ua" \
  ":ua\":{\"S\":\"$(TIMESTAMP)\"}"

aws s3 cp "$TARGET" "s3://$S3_BUCKET/$S3_KEY/" 2>>"$LOGFILE"

# 6) COMPLETED
ddb_update COMPLETED ", finishedAt = :ft" \
  ":ft\":{\"S\":\"$(TIMESTAMP)\"}"
