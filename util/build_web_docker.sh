#!/bin/bash
set -e

# This script builds and starts the web container
# It can handle no-cache option for fresh builds

# Detect which mode: development, production, or clean
MODE=${1:-dev}
ACTION=${2:-run}

if [ "$MODE" = "clean" ]; then
  echo "Cleaning up Docker resources..."
  (cd docker/web && docker-compose down -v --remove-orphans)
  exit 0
fi

if [ "$MODE" = "prod" ]; then
  TARGET="web-prod"
  echo "Building production web container..."
else
  TARGET="web-dev"
  echo "Building development web container..."
fi

# Check if no-cache option is specified
if [ "$ACTION" = "no-cache" ]; then
  echo "Using --no-cache option for a fresh build..."
  BUILD_OPTS="--no-cache"
  ACTION="run"  # Default to run after no-cache build
else
  BUILD_OPTS=""
fi

# Build the Docker image
(cd docker/web && docker-compose build $BUILD_OPTS $TARGET)

# Based on ACTION, either run the container or push the image
if [ "$ACTION" = "run" ]; then
  echo "Starting container..."
  (cd docker/web && docker-compose up -d $TARGET)
  echo "Web app running at http://localhost:3000 (dev) or http://localhost:3001 (prod)"
  echo "Use 'docker-compose logs -f $TARGET' to view logs"
elif [ "$ACTION" = "run-localstack" ]; then
  echo "Making sure LocalStack is running..."
  if ! docker ps | grep -q localstack; then
    echo "LocalStack not running. Starting..."
    (cd docker/localstack && docker-compose up -d)
    sleep 5  # Wait for LocalStack to initialize
  fi
  
  echo "Starting web container connected to LocalStack network..."
  (cd docker/web && docker-compose up -d $TARGET)
  echo "Web app running at http://localhost:3000 (dev) or http://localhost:3001 (prod)"
  echo "Connected to LocalStack at http://localstack:4566"
elif [ "$ACTION" = "push" ]; then
  echo "Pushing image to registry..."
  # Add your docker push commands here
  echo "Not implemented yet"
else
  echo "Unknown action: $ACTION. Valid options are: run, run-localstack, push, no-cache"
  exit 1
fi 