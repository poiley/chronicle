#!/bin/bash
# Reset and restart LocalStack with CORS enabled

set -e

echo "===== Stopping and removing LocalStack container ====="
docker compose -f docker/localstack/docker-compose.yml down
docker volume rm localstack_localstack_data || true
rm -f terraform/backend/lambda/dispatch_to_ecs.zip

echo "===== Starting LocalStack container ====="
docker compose -f docker/localstack/docker-compose.yml up -d
sleep 5

echo "===== Running LocalStack setup script with CORS enabled ====="
./docker/localstack/localstack_setup.sh

echo "===== LocalStack setup complete ====="
echo ""
echo "API URL for web app: http://localhost:4566"
echo ""
echo "To test the web frontend with Docker, run:"
echo "./util/build_web_docker.sh dev" 