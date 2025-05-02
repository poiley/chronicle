#!/bin/bash
set -e

echo "Creating necessary directories..."
mkdir -p data/downloads data/watch data/config

# Create config file if it doesn't exist
if [ ! -f data/config/s3-torrent-creator.json ]; then
  echo "Creating config file..."
  cat > data/config/s3-torrent-creator.json << EOF
{
  "bucket_name": "chronicle-recordings-dev",
  "prefix": "",
  "region": "us-east-1",
  "endpoint_url": "http://localstack:4566",
  "download_dir": "/downloads",
  "watch_dir": "/watch",
  "tracker_host": "tracker",
  "tracker_port": 6969,
  "poll_interval": 10,
  "aws_access_key_id": "test",
  "aws_secret_access_key": "test"
}
EOF
fi

# Step 1: Cleanup any existing containers
echo "Cleaning up previous containers..."
docker-compose -f docker-compose-simple.yml down 2>/dev/null || true
docker rm -f s3-torrent-creator 2>/dev/null || true

# Step 2: Build the dockerfile for the S3 torrent creator
echo "Building S3 torrent creator container..."
mkdir -p docker/s3-torrent-creator
docker build -t s3-torrent-creator -f docker/s3-torrent-creator/Dockerfile .

# Step 3: Start LocalStack and the tracker
echo "Starting LocalStack and tracker..."
docker-compose -f docker-compose-simple.yml up -d

# Wait for containers to start
echo "Waiting for containers to start..."
sleep 10

# Step 4: Create test bucket in LocalStack
echo "Creating test bucket in LocalStack..."
aws --endpoint-url=http://localhost:4566 s3 mb s3://chronicle-recordings-dev

# Step 5: Create a test file and upload it to S3
echo "Creating and uploading test file to S3..."
echo "This is a test file for S3 torrent download" > data/downloads/s3-test-file.txt
aws --endpoint-url=http://localhost:4566 s3 cp data/downloads/s3-test-file.txt s3://chronicle-recordings-dev/s3-test-file.txt

# Step 6: Start the S3 torrent creator container
echo "Starting S3 torrent creator container..."
docker run -d --name s3-torrent-creator \
  --network=chronicle-network \
  -v "$(pwd)/data/downloads:/downloads" \
  -v "$(pwd)/data/watch:/watch" \
  -v "$(pwd)/data/config:/config" \
  s3-torrent-creator

# Step 7: Wait for torrent to be created
echo "Waiting for torrent to be created (30 seconds)..."
sleep 30

# Step 8: Check if torrent was created
echo "Checking if torrent was created..."
if [ -f data/watch/s3-test-file.txt.torrent ]; then
  echo "Success! Torrent file was created."
else
  echo "Error: Torrent file was not created."
fi

# Step 9: List files in S3
echo "Listing files in S3 bucket:"
aws --endpoint-url=http://localhost:4566 s3 ls s3://chronicle-recordings-dev/

echo ""
echo "S3 Torrent demo complete."
echo "Transmission Web UI: http://localhost:9091"
echo "To view logs from the S3 torrent creator: docker logs s3-torrent-creator" 