#!/bin/bash
set -euo pipefail

docker build \
  -t chronicle-transmission:latest \
  -f docker/transmission/Dockerfile \
  docker/transmission 