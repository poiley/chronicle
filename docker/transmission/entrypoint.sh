#!/usr/bin/env bash
set -euo pipefail

# Debug: Show environment and file permissions
echo "Current user: $(whoami)"
echo "Home directory: $HOME"
echo "Working directory: $(pwd)"

# Create config directory if it doesn't exist
mkdir -p /config/transmission-home

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

# Start transmission-daemon in foreground
echo "Starting transmission-daemon to seed torrents..."
exec transmission-daemon --foreground --config-dir=/config/transmission-home 