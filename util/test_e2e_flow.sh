#!/bin/bash
set -eo pipefail

# This script tests the end-to-end flow of downloading a YouTube video,
# creating a torrent file, and seeding it via Transmission.

# Default YouTube URL and filename if not provided
YOUTUBE_URL=${1:-"https://www.youtube.com/watch?v=B38CY-4Rd6s"}
OUTPUT_FILENAME=${2:-"alive07.mkv"}

# Define container names and network
NETWORK_NAME="chronicle-network"
LOCALSTACK_CONTAINER="chronicle-localstack"
RECORDER_CONTAINER="chronicle-recorder"
TRANSMISSION_CONTAINER="chronicle-transmission"

# AWS configuration
BUCKET_NAME="chronicle-recordings-dev"
DDB_TABLE="jobs"
S3_KEY="recordings/$(date -u +%Y/%m/%d/)"
LOCALSTACK_ENDPOINT="http://localhost:4566"

# Generate a UUID for the job
if command -v uuidgen &>/dev/null; then
  JOB_ID=$(uuidgen)
else
  JOB_ID=$(cat /proc/sys/kernel/random/uuid)
fi

echo "=========================================================="
echo "🔄 Starting end-to-end test with the following parameters:"
echo "=========================================================="
echo "Job ID: $JOB_ID"
echo "YouTube URL: $YOUTUBE_URL"
echo "Output filename: $OUTPUT_FILENAME"
echo "S3 storage path: s3://$BUCKET_NAME/$S3_KEY"
echo "=========================================================="

echo "🔄 Running environment setup..."
./util/setup.sh

# Add a job to the queue
echo "🔄 Adding a job to the queue..."
QUEUE_URL=$(aws --endpoint-url=$LOCALSTACK_ENDPOINT sqs list-queues --query "QueueUrls[?contains(@, 'chronicle-jobs.fifo')]" --output text)
aws --endpoint-url="$LOCALSTACK_ENDPOINT" sqs send-message \
  --queue-url "$QUEUE_URL" \
  --message-body "{\"jobId\": \"$JOB_ID\", \"url\": \"$YOUTUBE_URL\", \"filename\": \"$OUTPUT_FILENAME\", \"s3Key\": \"$S3_KEY$OUTPUT_FILENAME\"}" \
  --message-group-id "default"
echo "🔄 Waiting for job to be processed..."
sleep 90
echo "🔄 Waited 90 seconds. Assuming job was processed, checking if file was uploaded to S3..."

# Check if file was uploaded to S3
echo "🔄 Checking if the file was uploaded to S3..."
RETRIES=10
for attempt in $(seq 1 $RETRIES); do
  if aws --endpoint-url="$LOCALSTACK_ENDPOINT" s3 ls "s3://$BUCKET_NAME/$S3_KEY$OUTPUT_FILENAME" &>/dev/null; then
    echo "✅ File uploaded to S3 successfully!"
    break
  else
    echo "❌ File not found in S3 bucket. Checking job status in DynamoDB... (attempt $attempt/$RETRIES)"
    JOB_STATUS=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" dynamodb get-item \
      --table-name "$DDB_TABLE" \
      --key '{"jobId": {"S": "'$JOB_ID'"}}' \
      --query 'Item.status.S' --output text 2>/dev/null)
    if [ "$JOB_STATUS" == "COMPLETED" ]; then
      echo "❌ Job is marked as COMPLETED in DynamoDB, but file is missing in S3."
      exit 1
    else
      echo "ℹ️ Job $JOB_ID is not marked as COMPLETED in DynamoDB (status: $JOB_STATUS). The job may still be in progress."
      if [ $attempt -lt $RETRIES ]; then
        echo "   Waiting 30 seconds before retrying..."
        sleep 30
      else
        echo "❌ Gave up after $RETRIES attempts. Job did not complete or file did not appear in S3."
        exit 1
      fi
    fi
  fi
done

# Check if torrent was created
echo "🔄 Checking if the torrent file was created..."
if aws --endpoint-url="$LOCALSTACK_ENDPOINT" s3 ls "s3://$BUCKET_NAME/watch/$OUTPUT_FILENAME.torrent" &>/dev/null; then
  echo "✅ Torrent file created successfully!"
else
  echo "❌ Torrent file not found in S3 bucket."
  exit 1
fi

# Check if Transmission picked up the torrent file
echo "🔄 Checking Transmission status... (waiting up to 30 seconds)"
for i in {1..30}; do
  echo -n "."
  if docker logs "$TRANSMISSION_CONTAINER" 2>&1 | grep -q "Added.*$OUTPUT_FILENAME"; then
    echo ""
    echo "✅ Transmission picked up the torrent file!"
    break
  fi
  sleep 1
  if [ $i -eq 30 ]; then
    echo ""
    echo "⚠️ Could not confirm if Transmission picked up the torrent. Check the logs:"
    docker logs "$TRANSMISSION_CONTAINER" | grep -i torrent || true
  fi
done

echo "=========================================================="
echo "🎉 End-to-end test completed successfully!"
echo "=========================================================="
echo "To clean up test containers, run:"
echo "docker rm -f $RECORDER_CONTAINER $TRANSMISSION_CONTAINER"
echo "To access Transmission web UI: http://localhost:9091"
echo "==========================================================" 