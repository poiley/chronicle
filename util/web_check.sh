#!/bin/bash
# Simple non-interactive status check for web and localstack containers

# Check web container
WEB_RUNNING=$(docker ps -q --filter "name=web-web-dev" | wc -l)
if [ "$WEB_RUNNING" -gt 0 ]; then
  echo "WEB CONTAINER: Running"
else
  echo "WEB CONTAINER: Not running"
fi

# Check LocalStack container
LS_RUNNING=$(docker ps -q --filter "name=localstack" | wc -l)
if [ "$LS_RUNNING" -gt 0 ]; then
  echo "LOCALSTACK: Running"
else
  echo "LOCALSTACK: Not running"
fi

# Instructions
echo ""
echo "COMMANDS:"
echo "- Start web:      docker compose -f docker/web/docker-compose.yml up -d web-dev"
echo "- Stop web:       docker compose -f docker/web/docker-compose.yml down"
echo "- Web logs:       docker logs web-web-dev-1"
echo "- Start backend:  docker compose -f docker/localstack/docker-compose.yml up -d" 