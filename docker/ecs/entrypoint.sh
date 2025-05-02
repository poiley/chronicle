#!/usr/bin/env bash
set -euo pipefail

# If AWS_ENDPOINT_URL is defined (LocalStack), include it on every aws call
# Additionally, set up AWS credentials for localstack run
if [[ -n "${AWS_ENDPOINT_URL:-}" ]]; then
  export AWS_ACCESS_KEY_ID="test"
  export AWS_SECRET_ACCESS_KEY="test"
  export AWS_REGION="us-west-1"
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

# Define trap for job status updates on exit
# This ensures job status is updated even if script exits unexpectedly
cleanup() {
  local exit_code=$?
  echo "Cleanup: exit_code=$exit_code" >> "$LOGFILE"
  
  if [ $exit_code -ne 0 ]; then
    # Update job status to FAILED if script exits with error
    err=$(tail -c 2048 "$LOGFILE" | sed 's/"/\\"/g')
    $AWS_CLI dynamodb update-item \
      --table-name "$DDB_TABLE" \
      --key "{\"jobId\":{\"S\":\"$JOB_ID\"}}" \
      --update-expression "SET #s = :s, finishedAt = :ft, errorDetail = :err" \
      --expression-attribute-names '{"#s":"status"}' \
      --expression-attribute-values "{\":s\":{\"S\":\"FAILED\"},\":ft\":{\"S\":\"$(TIMESTAMP)\"},\":err\":{\"S\":\"$err\"}}"
    echo "Job status updated to FAILED" >> "$LOGFILE"
  elif [ "$JOB_STATUS" != "COMPLETED" ]; then
    # If we haven't explicitly marked job as completed, do it now
    $AWS_CLI dynamodb update-item \
      --table-name "$DDB_TABLE" \
      --key "{\"jobId\":{\"S\":\"$JOB_ID\"}}" \
      --update-expression "SET #s = :s, finishedAt = :ft" \
      --expression-attribute-names '{"#s":"status"}' \
      --expression-attribute-values "{\":s\":{\"S\":\"COMPLETED\"},\":ft\":{\"S\":\"$(TIMESTAMP)\"}}"
    echo "Job status updated to COMPLETED" >> "$LOGFILE"
  fi
}

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

# Remove any trailing slashes from S3_KEY
S3_KEY=${S3_KEY%/}

# Create a copy in the shared volume for transmission
echo "Copying file to shared volume for seeding..."
# Make sure the downloads directory exists
mkdir -p /var/downloads
# Copy the file to the shared volume before uploading to S3
cp -v "$TARGET" "/var/downloads/$(basename "$TARGET")"

# Upload file to S3 with correct path (avoid path/file/file pattern)
$AWS_CLI s3 cp "$TARGET" "s3://$S3_BUCKET/$S3_KEY/$(basename "$TARGET")" 2>>"$LOGFILE"

# 6) CREATING TORRENT
ddb_update CREATING_TORRENT \
  ", creatingTorrentAt = :cta" \
  '":cta":{"S":"'"$(TIMESTAMP)"'"}'

# Get the full S3 path of the uploaded file
S3_FULL_PATH="s3://$S3_BUCKET/$S3_KEY/$(basename "$TARGET")"
TORRENT_FILE="/tmp/$(basename "$TARGET").torrent"

# Store torrent in the watch subfolder
TORRENT_S3_KEY="watch/$(basename "$TARGET").torrent"

# Ensure the watch folder exists
echo "Ensuring watch folder exists in S3 bucket..."
$AWS_CLI s3api head-object --bucket "$S3_BUCKET" --key "watch/" &>/dev/null || \
  $AWS_CLI s3api put-object --bucket "$S3_BUCKET" --key "watch/" --content-length 0

# Create torrent file with transmission-create
# Use the file in the shared volume instead of the original download location
transmission-create -o "$TORRENT_FILE" -c "Chronicle Livestream Recording" -t udp://23.252.56.60:6969 "/var/downloads/$(basename "$TARGET")"

# Upload torrent file to S3
$AWS_CLI s3 cp "$TORRENT_FILE" "s3://$S3_BUCKET/$TORRENT_S3_KEY" 2>>"$LOGFILE"

# Start transmission container to seed the torrent (if we're in LocalStack)
if [[ -n "${AWS_ENDPOINT_URL:-}" ]]; then
  # For local development, check if Docker is available
  if ! docker info &>/dev/null; then
    echo "Docker not available inside container. This is expected in LocalStack Lambda."
    echo "The torrent file has been uploaded to S3 and can be used by the transmission service."
  else
    # Docker is available, start transmission container
    docker run -d \
      --name "transmission-${JOB_ID}" \
      --network="chronicle-network" \
      --volumes-from chronicle-recorder \
      --volumes-from chronicle-transmission \
      -e "JOB_ID=$JOB_ID" \
      -e "DDB_TABLE=$DDB_TABLE" \
      -e "TORRENT_FILE=$TORRENT_FILE" \
      -e "SOURCE_FILE=$TARGET" \
      -e "S3_BUCKET=$S3_BUCKET" \
      -e "S3_KEY=$TORRENT_S3_KEY" \
      -e "AWS_ENDPOINT_URL=$AWS_ENDPOINT_URL" \
      chronicle-transmission
  fi
else
  # For production, we use ECS task
  aws ecs run-task \
    --cluster "${ECS_CLUSTER}" \
    --task-definition "${TRANSMISSION_TASK_DEF}" \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_IDS}],securityGroups=[${SECURITY_GROUP_IDS}],assignPublicIp=ENABLED}" \
    --overrides "{
      \"containerOverrides\": [{
        \"name\": \"chronicle-transmission\",
        \"environment\": [
          {\"name\": \"JOB_ID\", \"value\": \"$JOB_ID\"},
          {\"name\": \"DDB_TABLE\", \"value\": \"$DDB_TABLE\"},
          {\"name\": \"TORRENT_FILE\", \"value\": \"$TORRENT_FILE\"},
          {\"name\": \"SOURCE_FILE\", \"value\": \"$TARGET\"},
          {\"name\": \"S3_BUCKET\", \"value\": \"$S3_BUCKET\"},
          {\"name\": \"S3_KEY\", \"value\": \"$TORRENT_S3_KEY\"}
        ]
      }]
    }"
fi

# 7) Update DynamoDB with torrent info
ddb_update COMPLETED \
  ", finishedAt = :ft, torrentFile = :tf" \
  '":ft":{"S":"'"$(TIMESTAMP)"'"},":tf":{"S":"'"$TORRENT_S3_KEY"'"}'
