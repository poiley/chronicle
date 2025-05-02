#!/bin/bash
set -euo pipefail

# Script to detect the opentracker's public IP and configure it in all relevant files

# Determine the opentracker container name based on the environment
TRACKER_CONTAINER="torrent-tracker"

# Try to get IP from the container's shared file
get_tracker_ip() {
  # First try to get IP from the container (if running)
  if docker ps | grep -q "$TRACKER_CONTAINER"; then
    # Try to get IP from the shared file in the container
    IP=$(docker exec "$TRACKER_CONTAINER" cat /tmp/public-ip 2>/dev/null || echo "")
    
    if [ -n "$IP" ] && [ "$IP" != "127.0.0.1" ]; then
      echo "$IP"
      return 0
    fi
  fi
  
  # If that fails, try to get our own public IP
  IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me || curl -s https://icanhazip.com)
  if [ -n "$IP" ]; then
    echo "$IP"
    return 0
  fi
  
  # If everything fails, use a default
  echo "127.0.0.1"
  return 1
}

# Get tracker IP and port
TRACKER_IP=$(get_tracker_ip)
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
  SETUP_SCRIPT="docker/localstack/s3-torrent-lambda-setup.sh"
  if [ -f "$SETUP_SCRIPT" ]; then
    echo "Updating $SETUP_SCRIPT..."
    # Use sed to update the TRACKERS environment variable
    sed -i "s|TRACKERS=udp://opentracker.example.com:1337|TRACKERS=${TRACKER_URL}|g" "$SETUP_SCRIPT"
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
    # Use sed to update the transmission-create command
    sed -i "s|udp://opentracker.example.com:1337|${TRACKER_URL}|g" "$ENTRYPOINT_SCRIPT"
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
      # Use sed to update the default TRACKERS value
      sed -i "s|TRACKERS = os.environ.get('TRACKERS', 'udp://opentracker.example.com:1337')|TRACKERS = os.environ.get('TRACKERS', '${TRACKER_URL}')|g" "$LAMBDA_FILE"
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
    # Use sed to update the TRACKERS variable in the environment block
    sed -i "s|TRACKERS  = \"udp://opentracker.example.com:1337\"|TRACKERS  = \"${TRACKER_URL}\"|g" "$TF_FILE"
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