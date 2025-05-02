#!/bin/bash
set -e

echo "Creating necessary directories..."
mkdir -p data/downloads data/watch data/config

# Step 1: Cleanup any existing containers
echo "Cleaning up previous containers..."
docker-compose -f docker-compose-simple.yml down 2>/dev/null || true
docker rm -f chronicle-transmission 2>/dev/null || true

# Step 2: Build the transmission container
echo "Building transmission container..."
docker build -t chronicle-transmission-test -f docker/transmission/Dockerfile.simple docker/transmission

# Step 3: Start the transmission container
echo "Starting transmission container (seed)..."
docker-compose -f docker-compose-simple.yml up -d

# Wait for container to start
echo "Waiting for seed container to start..."
sleep 5

# Step 4: Create a small test file to be seeded
echo "Creating test file..."
echo "This is a test file for torrent download" > data/downloads/test-file.txt

# Step 5: Create torrent file
echo "Creating torrent file..."
docker exec chronicle-transmission transmission-create -t 'udp://tracker:6969/announce' -o /watch/test-file.torrent -c 'Test torrent' /downloads/test-file.txt

# Step 6: Start a leecher client in another container
echo "Starting leecher client to download the torrent..."
docker run --rm --entrypoint transmission-cli --network chronicle-network \
  -v "$(pwd)/data/downloads:/downloads" \
  -v "$(pwd)/data/watch:/watch" \
  chronicle-transmission-test \
  -w /downloads /watch/test-file.torrent

echo ""
echo "Torrent demo complete. Check data/downloads for the downloaded file and data/watch for the .torrent."
echo "Transmission Web UI (seed): http://localhost:9091" 