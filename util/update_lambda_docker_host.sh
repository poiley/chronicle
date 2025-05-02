#!/bin/bash
set -e

LOCALSTACK_ENDPOINT="http://localhost:4566"
REGION="us-west-1"

# Get all Lambda functions
echo "Getting all Lambda functions..."
FUNCTIONS=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" --region="$REGION" lambda list-functions --query 'Functions[*].FunctionName' --output text)

for FUNC in $FUNCTIONS; do
  echo "Updating Docker host for Lambda: $FUNC"
  
  # Get current configuration
  CONFIG=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" --region="$REGION" lambda get-function-configuration --function-name "$FUNC")
  
  # Check if Environment is already set
  if echo "$CONFIG" | grep -q '"Environment":'; then
    # Check if DOCKER_HOST is already set
    if echo "$CONFIG" | grep -q "DOCKER_HOST"; then
      echo "DOCKER_HOST already set for $FUNC, skipping"
      continue
    fi
    
    # Extract existing environment variables as JSON
    EXISTING_VARS=$(echo "$CONFIG" | grep -o '"Environment": {[^}]*}' | sed 's/"Environment": {"Variables": {//' | sed 's/}}//')
    
    # Add DOCKER_HOST to existing variables
    if [ -z "$EXISTING_VARS" ]; then
      NEW_VARS='{"DOCKER_HOST": "tcp://host.docker.internal:2375"}'
    else
      NEW_VARS="${EXISTING_VARS}, \"DOCKER_HOST\": \"tcp://host.docker.internal:2375\""
    fi
    
    # Update function configuration
    aws --endpoint-url="$LOCALSTACK_ENDPOINT" --region="$REGION" lambda update-function-configuration \
      --function-name "$FUNC" \
      --environment "{\"Variables\": {${NEW_VARS}}}"
  else
    # No environment variables set yet, create new environment
    aws --endpoint-url="$LOCALSTACK_ENDPOINT" --region="$REGION" lambda update-function-configuration \
      --function-name "$FUNC" \
      --environment '{"Variables": {"DOCKER_HOST": "tcp://host.docker.internal:2375"}}'
  fi
  
  echo "✅ Updated $FUNC"
done

echo "✅ All Lambda functions updated!" 