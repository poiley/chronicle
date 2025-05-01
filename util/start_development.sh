#!/bin/bash
set -e

# Start LocalStack if not already running
if ! docker ps | grep -q localstack; then
  echo "Starting LocalStack..."
  (cd docker/localstack && docker-compose up -d)
  
  # Wait for LocalStack to initialize
  echo "Waiting for LocalStack to be ready..."
  for i in {1..30}; do
    if curl -s http://localhost:4566/health | grep -q "\"s3\":{\"running\":true"; then
      echo "LocalStack is ready!"
      break
    fi
    echo -n "."
    sleep 1
  done
  
  # Initialize LocalStack services
  echo "Initializing LocalStack services..."
  ./docker/localstack/localstack_setup.sh
  
  # Configure CORS for API Gateway
  echo "Configuring CORS for API Gateway..."
  ./util/fix_localstack_cors.sh
else
  echo "LocalStack is already running."
fi

# Start web container connected to LocalStack
echo "Starting web container..."
./util/build_web_docker.sh dev run-localstack

echo ""
echo "Development environment is ready!"
echo "Web UI: http://localhost:3000"
echo "LocalStack: http://localhost:4566"
echo ""
echo "To view logs:"
echo "  - Web container: docker logs -f web-web-dev-1"
echo "  - LocalStack: docker logs -f localstack-localstack-1" 