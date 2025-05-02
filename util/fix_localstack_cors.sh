#!/bin/bash
# Script to properly enable CORS on LocalStack API Gateway

set -e

export AWS_PAGER=""
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_REGION=${AWS_REGION:-us-west-1}
export AWS_ENDPOINT_URL="http://localhost:4566"

echo "=== Fixing CORS headers on LocalStack API Gateway ==="

# Get API ID
API_ID=$(aws --endpoint-url=$AWS_ENDPOINT_URL apigateway get-rest-apis | jq -r '.items[0].id')
if [ -z "$API_ID" ]; then
  echo "❌ No API Gateway found! Please run the LocalStack setup first."
  exit 1
fi

echo "✅ Found API Gateway with ID: $API_ID"

# Get the /jobs resource ID
RESOURCES=$(aws --endpoint-url=$AWS_ENDPOINT_URL apigateway get-resources --rest-api-id $API_ID)
RESOURCE_ID=$(echo $RESOURCES | jq -r '.items[] | select(.pathPart=="jobs") | .id')

if [ -z "$RESOURCE_ID" ]; then
  echo "❌ Could not find /jobs resource! Please run the LocalStack setup first."
  exit 1
fi

echo "✅ Found /jobs resource with ID: $RESOURCE_ID"

# Add OPTIONS method if it doesn't exist
echo "Adding OPTIONS method with CORS headers..."
aws --endpoint-url=$AWS_ENDPOINT_URL apigateway put-method \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method OPTIONS \
  --authorization-type NONE

# Configure the OPTIONS mock integration
aws --endpoint-url=$AWS_ENDPOINT_URL apigateway put-integration \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method OPTIONS \
  --type MOCK \
  --request-templates '{"application/json": "{\"statusCode\": 200}"}'

# Add response methods for OPTIONS
aws --endpoint-url=$AWS_ENDPOINT_URL apigateway put-method-response \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method OPTIONS \
  --status-code 200 \
  --response-parameters '{
    "method.response.header.Access-Control-Allow-Headers": true,
    "method.response.header.Access-Control-Allow-Methods": true,
    "method.response.header.Access-Control-Allow-Origin": true
  }'

# Add integration response for OPTIONS
aws --endpoint-url=$AWS_ENDPOINT_URL apigateway put-integration-response \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method OPTIONS \
  --status-code 200 \
  --response-parameters '{
    "method.response.header.Access-Control-Allow-Headers": "'"'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"'",
    "method.response.header.Access-Control-Allow-Methods": "'"'GET,POST,OPTIONS'"'",
    "method.response.header.Access-Control-Allow-Origin": "'"'*'"'"
  }' \
  --response-templates '{"application/json": ""}'

# Add CORS headers to GET method response
aws --endpoint-url=$AWS_ENDPOINT_URL apigateway put-method-response \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method GET \
  --status-code 200 \
  --response-parameters '{
    "method.response.header.Access-Control-Allow-Origin": true
  }'

# Add CORS headers to GET integration response
aws --endpoint-url=$AWS_ENDPOINT_URL apigateway put-integration-response \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method GET \
  --status-code 200 \
  --response-parameters '{
    "method.response.header.Access-Control-Allow-Origin": "'"'*'"'"
  }'

# Add CORS headers to POST method response
aws --endpoint-url=$AWS_ENDPOINT_URL apigateway put-method-response \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method POST \
  --status-code 200 \
  --response-parameters '{
    "method.response.header.Access-Control-Allow-Origin": true
  }'

# Add CORS headers to POST integration response
aws --endpoint-url=$AWS_ENDPOINT_URL apigateway put-integration-response \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method POST \
  --status-code 200 \
  --response-parameters '{
    "method.response.header.Access-Control-Allow-Origin": "'"'*'"'"
  }'

# Deploy the API
echo "Deploying API to prod stage..."
DEPLOYMENT_ID=$(aws --endpoint-url=$AWS_ENDPOINT_URL apigateway create-deployment \
  --rest-api-id $API_ID \
  --stage-name prod | jq -r '.id')

echo "✅ API deployed with CORS headers (Deployment ID: $DEPLOYMENT_ID)"
echo "API URL: http://localhost:4566/restapis/$API_ID/prod/_user_request_"

# Print the web environment variable to use
echo ""
echo "For Docker container, set this environment variable:"
echo "NEXT_PUBLIC_API_URL=http://host.docker.internal:4566"
echo ""
echo "For local development, set this environment variable:"
echo "NEXT_PUBLIC_API_URL=http://localhost:4566" 