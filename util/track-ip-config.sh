#!/bin/bash
set -euo pipefail
trap 'echo "track-ip-config.sh failed at line $LINENO with exit code $?" >&2' ERR

echo "track-ip-config.sh: starting"
# Script to configure the opentracker's IP in all relevant files

# Use the opentracker container name from setup_fixed.sh
OPENTRACKER_CONTAINER="chronicle-opentracker"

# Get tracker IP from the container
get_tracker_ip() {
  # Try to get IP from the container
  if docker ps | grep -q "$OPENTRACKER_CONTAINER"; then
    IP=$(docker exec "$OPENTRACKER_CONTAINER" cat /tmp/public-ip 2>/dev/null || echo "")
    if [ -n "$IP" ] && [ "$IP" != "127.0.0.1" ]; then
      echo "$IP"
      return 0
    fi
  fi
  
  echo "Error: Opentracker container not running or IP not detected"
  return 1
}

# Get tracker IP and port
TRACKER_IP=$(get_tracker_ip)
if [ $? -ne 0 ]; then
  echo "Failed to get tracker IP. Is the opentracker container running?"
  echo "Run setup_fixed.sh first to ensure the opentracker container is up."
  exit 1
fi

TRACKER_PORT=6969
TRACKER_URL="udp://${TRACKER_IP}:${TRACKER_PORT}"

echo "Using tracker URL: $TRACKER_URL"

# Update tracker-config.json
update_tracker_config() {
  CONFIG_FILE="terraform/backend/lambda/tracker-config.json"
  if [ -f "$CONFIG_FILE" ]; then
    echo "Updating $CONFIG_FILE..."
    cat > "$CONFIG_FILE" << EOF
{
  "trackers": {
    "primary": "${TRACKER_URL}",
    "fallback": []
  },
  "torrent_options": {
    "comment": "Chronicle Livestream Recording",
    "piece_length": 16384
  }
}
EOF
  else
    echo "Warning: $CONFIG_FILE not found, skipping"
  fi
}

# Update Lambda environment in LocalStack setup
update_lambda_env() {
  SETUP_SCRIPT="docker/localstack/torrent_lambda_setup.sh"
  if [ -f "$SETUP_SCRIPT" ]; then
    echo "Updating $SETUP_SCRIPT..."
    sed -i "s|TRACKERS=udp://[^:]*:[0-9]*|TRACKERS=${TRACKER_URL}|g" "$SETUP_SCRIPT"
    echo "Updated $SETUP_SCRIPT"
  else
    echo "Warning: $SETUP_SCRIPT not found, skipping"
  fi
}

# Update entrypoint.sh in docker/ecs
update_entrypoint() {
  ENTRYPOINT_SCRIPT="docker/ecs/entrypoint.sh"
  if [ -f "$ENTRYPOINT_SCRIPT" ]; then
    echo "Updating $ENTRYPOINT_SCRIPT..."
    sed -i "s|udp://[^:]*:[0-9]*|${TRACKER_URL}|g" "$ENTRYPOINT_SCRIPT"
    echo "Updated $ENTRYPOINT_SCRIPT"
  else
    echo "Warning: $ENTRYPOINT_SCRIPT not found, skipping"
  fi
}

# Update Lambda functions' default tracker
update_lambda_files() {
  for LAMBDA_FILE in terraform/backend/lambda/s3_torrent_creator.py terraform/backend/lambda/s3_torrent_creator_local.py; do
    if [ -f "$LAMBDA_FILE" ]; then
      echo "Updating $LAMBDA_FILE..."
      sed -i "s|TRACKERS = os.environ.get('TRACKERS', 'udp://[^:]*:[0-9]*')|TRACKERS = os.environ.get('TRACKERS', '${TRACKER_URL}')|g" "$LAMBDA_FILE"
      echo "Updated $LAMBDA_FILE"
    else
      echo "Warning: $LAMBDA_FILE not found, skipping"
    fi
  done
}

# Update Terraform configuration
update_terraform() {
  TF_FILE="terraform/backend/s3-torrent-lambda.tf"
  if [ -f "$TF_FILE" ]; then
    echo "Updating $TF_FILE..."
    sed -i "s|TRACKERS  = \"udp://[^:]*:[0-9]*\"|TRACKERS  = \"${TRACKER_URL}\"|g" "$TF_FILE"
    echo "Updated $TF_FILE"
  else
    echo "Warning: $TF_FILE not found, skipping"
  fi
}

# Run all update functions
update_tracker_config
update_lambda_env
update_entrypoint
update_lambda_files
update_terraform

echo "Tracker configuration complete! All components now use: $TRACKER_URL"
echo "Remember to rebuild any containers or redeploy Lambda functions for changes to take effect." 