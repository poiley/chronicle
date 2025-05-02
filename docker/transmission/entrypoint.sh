#!/usr/bin/env bash
set -euo pipefail

# Debug: Show environment and file permissions
echo "Current user: $(whoami)"
echo "Home directory: $HOME"
echo "Working directory: $(pwd)"

# Get S3 bucket name from environment, with a default for development
S3_BUCKET=${S3_BUCKET:-"chronicle-recordings-dev"}
# Determine AWS endpoint (use default AWS endpoint or LocalStack for dev)
AWS_ENDPOINT=${AWS_ENDPOINT:-""}
AWS_REGION=${AWS_REGION:-"us-west-1"}

# Setup AWS CLI command with endpoint if provided
if [ -n "$AWS_ENDPOINT" ]; then
  AWS_CLI="aws --endpoint-url=$AWS_ENDPOINT"
else
  AWS_CLI="aws"
fi

# Create config directory if it doesn't exist
mkdir -p /config/transmission-home
mkdir -p /watch

# Create settings.json with appropriate configuration
cat > /config/transmission-home/settings.json << EOF
{
  "download-dir": "/downloads",
  "incomplete-dir": "/downloads/incomplete",
  "incomplete-dir-enabled": true,
  "rpc-authentication-required": false,
  "rpc-bind-address": "0.0.0.0",
  "rpc-enabled": true,
  "rpc-port": 9091,
  "rpc-whitelist": "127.0.0.1,192.168.*.*",
  "rpc-whitelist-enabled": false,
  "rpc-host-whitelist": "",
  "rpc-host-whitelist-enabled": false,
  "watch-dir": "/watch",
  "watch-dir-enabled": true,
  "peer-port-random-on-start": true
}
EOF

# Function to sync torrents from S3 watch folder to local watch directory
sync_s3_watch_folder() {
  echo "Syncing torrents from S3 watch folder to local watch directory..."
  $AWS_CLI s3 sync "s3://$S3_BUCKET/watch/" /watch/ --exclude "*" --include "*.torrent" --region $AWS_REGION
  echo "S3 sync completed at $(date)"
}

# Initial sync from S3
sync_s3_watch_folder

# Start periodic sync process in the background
(
  while true; do
    # Wait for 60 seconds
    sleep 60
    # Sync from S3
    sync_s3_watch_folder
  done
) &

# Store the background job PID
SYNC_PID=$!

# Trap to kill the sync process when transmission terminates
trap "kill $SYNC_PID 2>/dev/null || true" EXIT

# Start transmission-daemon in foreground
echo "Starting transmission-daemon to seed torrents..."
exec transmission-daemon --foreground --config-dir=/config/transmission-home 