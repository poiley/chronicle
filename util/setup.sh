#!/bin/bash
set -eo pipefail

# This script sets up the development environment with proper network configuration,
# cleaning all custom images and containers first, and fixes common issues with Windows WSL

# Define constants
NETWORK_NAME="chronicle-network"
LOCALSTACK_CONTAINER="chronicle-localstack"
WEB_CONTAINER="web-web-dev-1"
RECORDER_CONTAINER="chronicle-recorder"
TRANSMISSION_CONTAINER="chronicle-transmission"
OPENTRACKER_CONTAINER="chronicle-opentracker"

# Define bucket and table names (matching localstack setup)
S3_BUCKET="chronicle-recordings-dev"
DDB_TABLE="jobs"

echo "====================================================="
echo "🚀 Setting up Chronicle development environment"
echo "====================================================="

# Check if Docker is running
if ! docker info &>/dev/null; then
  echo "❌ Docker is not running. Please start Docker and try again."
  exit 1
fi

# Check if Docker TCP daemon is exposed
echo "🔄 Checking Docker TCP daemon..."
if ! curl -s http://localhost:2375/version > /dev/null; then
  echo "❌ Docker TCP daemon is not available on port 2375."
  echo "Please follow these steps in Docker Desktop:"
  echo "  1. Open Docker Desktop"
  echo "  2. Go to Settings"
  echo "  3. Under 'General', check 'Expose daemon on tcp://localhost:2375 without TLS'"
  echo "  4. Click 'Apply & Restart'"
  echo "  5. Run this script again"
  exit 1
else
  echo "✅ Docker TCP daemon is properly configured"
fi

# Stop all related containers
echo "🔄 Stopping all containers..."
docker ps -a | grep -E "$LOCALSTACK_CONTAINER|$WEB_CONTAINER|$RECORDER_CONTAINER|$TRANSMISSION_CONTAINER|$OPENTRACKER_CONTAINER|web-web|chronicle" | awk '{print $1}' | xargs docker rm -f 2>/dev/null || true

# Remove all related images
echo "🔄 Removing all custom images..."
docker images | grep -E "chronicle|web-web" | awk '{print $1":"$2}' | xargs docker rmi -f 2>/dev/null || true

# Prune any dangling images
echo "🔄 Pruning dangling images..."
docker image prune -f

# Clean all volumes
echo "🔄 Removing and recreating volumes..."
for VOLUME in chronicle_downloads chronicle_watch chronicle_config localstack_data; do
  docker volume rm $VOLUME 2>/dev/null || true
  docker volume create $VOLUME
done

# Remove network if it exists
echo "🔄 Removing existing network..."
docker network rm "$NETWORK_NAME" 2>/dev/null || true

# Create network
echo "🔄 Creating Docker network $NETWORK_NAME..."
docker network create "$NETWORK_NAME"

# Start LocalStack with fresh configuration
echo "🔄 Starting LocalStack..."
docker run -d --name "$LOCALSTACK_CONTAINER" \
  --network="$NETWORK_NAME" \
  -p 4566:4566 \
  -e SERVICES=s3,sqs,dynamodb,lambda,apigateway \
  -e DEBUG=1 \
  -e AWS_ACCESS_KEY_ID=test \
  -e AWS_SECRET_ACCESS_KEY=test \
  -e AWS_DEFAULT_REGION=us-west-1 \
  -e LAMBDA_EXECUTOR=docker \
  -v "/var/run/docker.sock:/var/run/docker.sock" \
  -v "localstack_data:/data" \
  localstack/localstack:latest

# Wait for LocalStack to initialize
echo "🔄 Waiting for LocalStack to be ready..."
MAX_WAIT=60
counter=0
while [ $counter -lt $MAX_WAIT ]; do
  if response=$(curl -s http://localhost:4566/_localstack/health) && echo "$response" | grep -q '"services"'; then
    echo "✅ LocalStack is ready!"
    break
  fi
  echo -n "."
  sleep 1
  counter=$((counter + 1))
  
  if [ $counter -eq $MAX_WAIT ]; then
    echo ""
    echo "❌ LocalStack didn't become ready in time. Check logs:"
    docker logs "$LOCALSTACK_CONTAINER"
    exit 1
  fi
done

# Initialize LocalStack services
echo "🔄 Initializing LocalStack services..."
./docker/localstack/localstack_setup.sh

# Configure CORS for API Gateway
echo "🔄 Configuring CORS for API Gateway..."
./util/fix_localstack_cors.sh

# Configure tracker with actual IP
if [ -f "./util/track-ip-config.sh" ]; then
  echo "🔄 Configuring tracker IP..."
  chmod +x ./util/track-ip-config.sh
  ./util/track-ip-config.sh
else
  echo "❌ Tracker IP configuration script not found"
fi

# Set up S3 torrent Lambda
echo "🔄 Setting up S3 torrent Lambda..."
./docker/localstack/s3-torrent-lambda-setup.sh

# Update all Lambda functions to use Docker TCP
echo "🔄 Configuring Lambda functions to use Docker TCP..."
./util/update_lambda_docker_host.sh

# Build recorder and transmission images with no cache
echo "🔄 Building recorder image with no cache..."
docker build --no-cache -t chronicle-recorder:latest -f docker/ecs/Dockerfile docker/ecs

echo "🔄 Building transmission image with no cache..."
docker build --no-cache -t chronicle-transmission:latest -f docker/transmission/Dockerfile docker/transmission

# Build and start web container with no cache
echo "🔄 Starting web container..."
./util/build_web_docker.sh dev no-cache

# Start transmission container for seeding torrents
echo "🔄 Starting transmission container..."
docker run -d \
  --name "$TRANSMISSION_CONTAINER" \
  --network="$NETWORK_NAME" \
  -p 9091:9091 \
  -p 51413:51413 \
  -p 51413:51413/udp \
  -v chronicle_downloads:/downloads \
  -v chronicle_watch:/watch \
  -v chronicle_config:/config \
  -e S3_BUCKET="$S3_BUCKET" \
  -e AWS_ENDPOINT_URL="http://$LOCALSTACK_CONTAINER:4566" \
  -e AWS_REGION=us-west-1 \
  -e AWS_ACCESS_KEY_ID=test \
  -e AWS_SECRET_ACCESS_KEY=test \
  chronicle-transmission:latest

# Build and start opentracker container
echo "🔄 Building opentracker image with no cache..."
cd docker/opentracker && docker build --no-cache -t chronicle-opentracker:latest . && cd ../..

echo "🔄 Starting opentracker container..."
docker run -d \
  --name "$OPENTRACKER_CONTAINER" \
  --network="$NETWORK_NAME" \
  -p 6969:6969 \
  -p 6969:6969/udp \
  chronicle-opentracker:latest

# Let the user know we're done
echo ""
echo "✅ Development environment is ready!"
echo "====================================================="
echo "Web UI: http://localhost:3000"
echo "LocalStack: http://localhost:4566"
echo "Transmission UI: http://localhost:9091"
echo "Opentracker: udp://localhost:6969"
echo "====================================================="
echo ""
echo "To view logs:"
echo "  - Web container: docker logs -f $WEB_CONTAINER"
echo "  - LocalStack: docker logs -f $LOCALSTACK_CONTAINER"
echo "  - Transmission: docker logs -f $TRANSMISSION_CONTAINER"
echo "  - Opentracker: docker logs -f $OPENTRACKER_CONTAINER"
echo ""
echo "To test the full workflow, run:"
echo "  ./util/test_e2e_flow.sh <youtube_url> <output_filename>"
echo ""
echo "To check and fix job statuses (recommended for LocalStack), run:"
echo "  ./util/check_and_fix_job_status.sh"
echo "=====================================================" 