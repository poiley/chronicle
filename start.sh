#!/bin/bash
set -euo pipefail

echo "Building containers..."
./util/build_backend_docker.sh
./util/build_transmission_docker.sh

echo "Cleaning up any previous containers..."
docker-compose down -v

echo "Starting Docker Compose..."
docker-compose up -d recorder transmission

echo "Waiting for containers to start..."
sleep 3

echo "Starting LocalStack container separately..."
docker-compose up -d localstack

echo "Waiting for LocalStack to become ready (max 60 seconds)..."
MAX_WAIT=60
count=0
while [ $count -lt $MAX_WAIT ]; do
    if curl -s "http://localhost:4566/health" | grep -q "\"s3\".*\"running\""; then
        echo "LocalStack is ready!"
        break
    fi
    echo "Waiting for LocalStack... $count/$MAX_WAIT"
    sleep 2
    count=$((count + 2))
done

if [ $count -ge $MAX_WAIT ]; then
    echo "ERROR: LocalStack did not become ready in time."
    echo "Checking container logs..."
    docker-compose logs localstack
    echo "You may need to stop all containers and try again:"
    echo "  docker-compose down -v"
    exit 1
fi

echo "Setting up LocalStack..."
./docker/localstack/localstack_setup.sh || {
    echo "ERROR: LocalStack setup failed."
    echo "Checking container logs..."
    docker-compose logs localstack
    exit 1
}

echo "Starting web interface..."
docker-compose up -d web

echo "System is running!"
echo "Web UI: http://localhost:3000"
echo "LocalStack UI: http://localhost:4566"
echo "Transmission UI: http://localhost:9091" 