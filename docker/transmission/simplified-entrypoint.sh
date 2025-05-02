#!/bin/sh
set -e

# Set up transmission configuration
mkdir -p /config/transmission-home
cat > /config/transmission-home/settings.json << EOF
{
  "download-dir": "/downloads",
  "incomplete-dir": "/downloads/incomplete",
  "incomplete-dir-enabled": true,
  "rpc-authentication-required": false,
  "rpc-bind-address": "0.0.0.0",
  "rpc-enabled": true,
  "rpc-port": 9091,
  "rpc-whitelist": "*.*.*.*",
  "rpc-whitelist-enabled": false,
  "watch-dir": "/watch",
  "watch-dir-enabled": true,
  "peer-port": 51415,
  "peer-port-random-on-start": false,
  "dht-enabled": true,
  "pex-enabled": true
}
EOF

# Create incomplete dir
mkdir -p /downloads/incomplete

# Start transmission-daemon in foreground
echo "Starting transmission-daemon to seed torrents..."
exec transmission-daemon --foreground --config-dir=/config/transmission-home 