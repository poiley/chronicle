#!/bin/bash
set -e

# This script helps fix a LocalStack-specific issue where job statuses might not be properly updated
# It checks for jobs that are in RECORDING state but have been idle for too long and marks them as COMPLETED

# Usage: ./check_and_fix_job_status.sh
# This script should be run periodically in a development environment

# Configuration
ENDPOINT_URL="http://localhost:4566"
REGION="us-west-1"
DDB_TABLE="jobs"
IDLE_THRESHOLD=300  # 5 minutes in seconds

# Get current timestamp
NOW=$(date +%s)

# Get all jobs
echo "📋 Fetching all jobs..."
JOBS=$(aws --endpoint-url="$ENDPOINT_URL" --region="$REGION" dynamodb scan \
  --table-name "$DDB_TABLE" \
  --select ALL_ATTRIBUTES \
  --filter-expression "#s = :recording OR #s = :uploading OR #s = :creating" \
  --expression-attribute-names '{"#s":"status"}' \
  --expression-attribute-values '{":recording":{"S":"RECORDING"}, ":uploading":{"S":"UPLOADING"}, ":creating":{"S":"CREATING_TORRENT"}}' \
  --output json)

# Parse jobs and check for idle ones
if [[ $(echo "$JOBS" | jq -r '.Count') -eq 0 ]]; then
  echo "✅ No jobs in RECORDING, UPLOADING, or CREATING_TORRENT state found."
  exit 0
fi

echo "🔍 Checking jobs for completion status..."
echo "$JOBS" | jq -r '.Items[] | "\(.jobId.S)|\(.status.S)|\(.lastHeartbeat.S)|\(.s3Key.S)|\(.filename.S)"' | while IFS='|' read -r JOB_ID STATUS LAST_HEARTBEAT S3_KEY FILENAME; do
  # Convert ISO timestamp to epoch for comparison
  if [[ -z "$LAST_HEARTBEAT" ]]; then
    echo "⏩ Job $JOB_ID has no lastHeartbeat, skipping"
    continue
  fi
  
  # Check if we have a valid S3 object that suggests the job completed
  TORRENT_PATH="watch/${FILENAME}.torrent"
  if aws --endpoint-url="$ENDPOINT_URL" --region="$REGION" s3 ls "s3://chronicle-recordings-dev/$TORRENT_PATH" &>/dev/null; then
    echo "🔄 Job $JOB_ID has a torrent file, but is still in $STATUS state. Marking as COMPLETED..."
    
    aws --endpoint-url="$ENDPOINT_URL" --region="$REGION" dynamodb update-item \
      --table-name "$DDB_TABLE" \
      --key "{\"jobId\":{\"S\":\"$JOB_ID\"}}" \
      --update-expression "SET #s = :s, finishedAt = :ft, torrentFile = :tf" \
      --expression-attribute-names '{"#s":"status"}' \
      --expression-attribute-values "{\":s\":{\"S\":\"COMPLETED\"},\":ft\":{\"S\":\"$(date -Iseconds -u)\"},\":tf\":{\"S\":\"$TORRENT_PATH\"}}"
      
    echo "✅ Job $JOB_ID marked as COMPLETED"
  else
    # Get last update time in seconds
    LAST_UPDATE=$(date -d "$LAST_HEARTBEAT" +%s 2>/dev/null || echo 0)
    IDLE_TIME=$((NOW - LAST_UPDATE))
    
    if [[ $IDLE_TIME -gt $IDLE_THRESHOLD ]]; then
      echo "⚠️ Job $JOB_ID has been idle for $IDLE_TIME seconds (threshold: $IDLE_THRESHOLD)."
      
      # Check if media file exists in S3
      if [[ -n "$S3_KEY" && -n "$FILENAME" ]]; then
        MEDIA_PATH="${S3_KEY%/}/${FILENAME}"
        if aws --endpoint-url="$ENDPOINT_URL" --region="$REGION" s3 ls "s3://chronicle-recordings-dev/$MEDIA_PATH" &>/dev/null; then
          echo "🔄 Job $JOB_ID appears to be complete (file exists in S3). Marking as COMPLETED..."
          
          aws --endpoint-url="$ENDPOINT_URL" --region="$REGION" dynamodb update-item \
            --table-name "$DDB_TABLE" \
            --key "{\"jobId\":{\"S\":\"$JOB_ID\"}}" \
            --update-expression "SET #s = :s, finishedAt = :ft" \
            --expression-attribute-names '{"#s":"status"}' \
            --expression-attribute-values "{\":s\":{\"S\":\"COMPLETED\"},\":ft\":{\"S\":\"$(date -Iseconds -u)\"}}"
            
          echo "✅ Job $JOB_ID marked as COMPLETED"
        else
          echo "❌ Job $JOB_ID appears to have failed (no file in S3). Marking as FAILED..."
          
          aws --endpoint-url="$ENDPOINT_URL" --region="$REGION" dynamodb update-item \
            --table-name "$DDB_TABLE" \
            --key "{\"jobId\":{\"S\":\"$JOB_ID\"}}" \
            --update-expression "SET #s = :s, finishedAt = :ft, errorDetail = :err" \
            --expression-attribute-names '{"#s":"status"}' \
            --expression-attribute-values "{\":s\":{\"S\":\"FAILED\"},\":ft\":{\"S\":\"$(date -Iseconds -u)\"},\":err\":{\"S\":\"Job timed out after $IDLE_TIME seconds without progress\"}}"
            
          echo "❌ Job $JOB_ID marked as FAILED"
        fi
      fi
    else
      echo "⏳ Job $JOB_ID is still active (idle for $IDLE_TIME seconds)"
    fi
  fi
done

echo "✅ Job status check completed!" 