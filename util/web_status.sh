#!/bin/bash
# Check status of web container and provide helpful commands

echo "=== Chronicle Web Frontend Status ==="

# Check if container is running
if docker ps | grep -q web-web-dev; then
  echo "✅ Web container is RUNNING"
  echo "• Web URL: http://localhost:3000"
  
  # Check if we can access the web app
  if curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 | grep -q "200\|304"; then
    echo "✅ Web frontend is ACCESSIBLE"
  else
    echo "❌ Web frontend is NOT ACCESSIBLE (container is running but site can't be reached)"
  fi
else
  echo "❌ Web container is NOT RUNNING"
fi

# Check if LocalStack is running
if docker ps | grep -q localstack; then
  echo "✅ LocalStack is RUNNING"
  
  # Check if LocalStack is healthy
  if curl -s http://localhost:4566/_localstack/health | grep -q "running"; then
    echo "✅ LocalStack is HEALTHY"
  else
    echo "❌ LocalStack is NOT HEALTHY"
  fi
else
  echo "❌ LocalStack is NOT RUNNING"
fi

echo -e "\n=== Common Commands ==="
echo "• Start web container:         ./util/build_web_docker.sh dev"
echo "• View web container logs:     ./util/build_web_docker.sh logs"
echo "• Stop web container:          docker compose -f docker/web/docker-compose.yml down"
echo "• Restart web container:       docker compose -f docker/web/docker-compose.yml restart web-dev"
echo "• Start LocalStack:            docker compose -f docker/localstack/docker-compose.yml up -d"
echo "• Reset LocalStack:            ./util/reset_localstack_cors.sh" 