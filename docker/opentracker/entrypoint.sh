#!/bin/sh

# Print startup banner
echo "==============================================="
echo "Starting Chronicle Opentracker (IPv4 Edition)"
echo "==============================================="

# Print system information
echo "Network Configuration:"
ip addr | grep -v "valid_forever" | grep -v "preferred_forever"

# Add timestamp to log entries
timestamp() {
  while read -r line; do
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $line"
  done
}

# Get the public IP address of the container
detect-ip > /tmp/public_ip
PUBLIC_IP=$(cat /tmp/public_ip)
echo "Public IP: $PUBLIC_IP"

# Run opentracker in the foreground
echo "Starting opentracker on port 6969 (TCP & UDP)..."
exec /usr/local/bin/opentracker -i 0.0.0.0 -p 6969 -P 6969 2>&1 | timestamp