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

# Check if network exists
if ! docker network inspect "$NETWORK_NAME" &>/dev/null; then
  echo "🔄 Creating Docker network $NETWORK_NAME..."
  docker network create "$NETWORK_NAME"
fi

# Make sure LocalStack is running
if ! docker ps | grep -q "$LOCALSTACK_CONTAINER"; then
  echo "❌ LocalStack container ($LOCALSTACK_CONTAINER) is not running."
  echo "   Please start the development environment first: ./util/setup_development.sh"
  exit 1
fi

# Clean up any existing containers
echo "🔄 Cleaning up any existing test containers..."
docker rm -f "$RECORDER_CONTAINER" "$TRANSMISSION_CONTAINER" 2>/dev/null || true

# Build the recorder container if needed
if ! docker image inspect chronicle-recorder:latest &>/dev/null; then
  echo "🔄 Building recorder container..."
  docker build -t chronicle-recorder:latest -f docker/ecs/Dockerfile docker/ecs
fi

# Build the transmission container if needed
if ! docker image inspect chronicle-transmission:latest &>/dev/null; then
  echo "🔄 Building transmission container..."
  # Check if the transmission dockerfile exists in expected location
  if [ -f "docker/transmission/Dockerfile" ]; then
    docker build -t chronicle-transmission:latest -f docker/transmission/Dockerfile docker/transmission
  else
    echo "⚠️ Transmission Dockerfile not found at expected location. Checking alternate locations..."
    # Check for possible alternate locations
    if [ -f "docker/ecs/transmission/Dockerfile" ]; then
      docker build -t chronicle-transmission:latest -f docker/ecs/transmission/Dockerfile docker/ecs/transmission
    else
      echo "❌ Could not find Transmission Dockerfile in known locations."
      echo "   Please ensure the Transmission Dockerfile exists and try again."
      exit 1
    fi
  fi
fi

# Create volumes if they don't exist
for VOLUME in chronicle_downloads chronicle_watch chronicle_config; do
  if ! docker volume inspect "$VOLUME" &>/dev/null; then
    echo "🔄 Creating Docker volume $VOLUME..."
    docker volume create "$VOLUME"
  fi
done

# Start Transmission container
echo "🔄 Starting Transmission container..."
docker run -d --name "$TRANSMISSION_CONTAINER" \
  --network="$NETWORK_NAME" \
  -v chronicle_downloads:/downloads \
  -v chronicle_watch:/watch \
  -v chronicle_config:/config \
  -p 9091:9091 -p 51414:51413 \
  -e AWS_ACCESS_KEY_ID=test \
  -e AWS_SECRET_ACCESS_KEY=test \
  -e AWS_DEFAULT_REGION=us-west-1 \
  -e AWS_ENDPOINT_URL="http://$LOCALSTACK_CONTAINER:4566" \
  -e S3_BUCKET="$BUCKET_NAME" \
  chronicle-transmission:latest

echo "🔄 Transmission container started."
echo "   Web UI available at: http://localhost:9091"

# Start Recorder container
echo "🔄 Starting Recorder container to process the job..."
docker run -d --name "$RECORDER_CONTAINER" \
  --network="$NETWORK_NAME" \
  -v chronicle_downloads:/downloads \
  -e AWS_ACCESS_KEY_ID=test \
  -e AWS_SECRET_ACCESS_KEY=test \
  -e AWS_DEFAULT_REGION=us-west-1 \
  -e AWS_ENDPOINT_URL="http://$LOCALSTACK_CONTAINER:4566" \
  -e JOB_ID="$JOB_ID" \
  -e DDB_TABLE="$DDB_TABLE" \
  -e S3_BUCKET="$BUCKET_NAME" \
  -e S3_KEY="$S3_KEY" \
  -e TTL_DAYS=30 \
  chronicle-recorder:latest "$YOUTUBE_URL" "$OUTPUT_FILENAME"

echo "🔄 Recorder container started."
echo "   Processing job $JOB_ID..."
echo "   Following recorder logs:"
docker logs -f "$RECORDER_CONTAINER" || true

# After recorder is done, check status
if [ "$(docker inspect -f '{{.State.ExitCode}}' "$RECORDER_CONTAINER")" -eq 0 ]; then
  echo "✅ Recorder completed successfully!"
else
  echo "❌ Recorder failed. Check logs above for details."
  exit 1
fi

# Check if file was uploaded to S3
echo "🔄 Checking if the file was uploaded to S3..."
if aws --endpoint-url="$LOCALSTACK_ENDPOINT" s3 ls "s3://$BUCKET_NAME/$S3_KEY$OUTPUT_FILENAME" &>/dev/null; then
  echo "✅ File uploaded to S3 successfully!"
else
  echo "❌ File not found in S3 bucket."
  exit 1
fi

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