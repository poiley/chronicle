#!/usr/bin/env bash
set -euo pipefail

# Dummy AWS creds so aws CLI works against LocalStack
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_REGION=${AWS_REGION:-us-east-1}
export ENVIRONMENT=${ENVIRONMENT:-dev}

LOCALSTACK_HOST=${LOCALSTACK_HOST:-localhost}
export AWS_ENDPOINT_URL="http://$LOCALSTACK_HOST:4566"
AWS_CLI="aws --endpoint-url $AWS_ENDPOINT_URL"

# Disable AWS CLI paging in scripts
export AWS_PAGER=""

echo "⏳ Waiting for LocalStack to be ready…"
while true; do
  # Try Pro endpoint first, then OSS endpoint
  for ep in /_localstack/health /health; do
    status_json=$(curl -fs "$AWS_ENDPOINT_URL${ep}" || true)
    if echo "$status_json" | grep -qE '"s3".*"running"'; then
      echo "✅ LocalStack is up!"
      break 2
    fi
  done
  sleep 2
done
echo "✅ LocalStack is up!"

# Configuration (override via env if desired)
S3_BUCKET="${S3_BUCKET:-chronicle-recordings-${ENVIRONMENT}}"
DDB_TABLE=${DDB_TABLE:-jobs}
QUEUE_NAME=${QUEUE_NAME:-chronicle-jobs.fifo}
DLQ_NAME=${DLQ_NAME:-chronicle-jobs-dlq.fifo}
LAMBDA_NAME=${LAMBDA_NAME:-dispatch-to-ecs}
LAMBDA_SRC_DIR="terraform/backend/lambda"
LAMBDA_ZIP="${LAMBDA_SRC_DIR}/dispatch_to_ecs.zip"
API_NAME=${API_NAME:-chronicle-api}
ECS_CLUSTER=${ECS_CLUSTER:-local-cluster}

# 1) Package the Lambda if missing
if [ ! -f "$LAMBDA_ZIP" ]; then
  echo "📦 Vendoring requests and packaging Lambda into $LAMBDA_ZIP"
  TMPDIR=$(mktemp -d)
  REPO_ROOT=$(pwd)                # record your repo root

  # Install requests (and its deps) into TMPDIR
  python3 -m pip install requests docker -t "$TMPDIR"

  # Copy your handler
  cp "$LAMBDA_SRC_DIR/dispatch_to_ecs.py" "$TMPDIR/"

  # Create the ZIP from inside TMPDIR, but write it back to the repo
  (
    cd "$TMPDIR"
    zip -r9 "$REPO_ROOT/$LAMBDA_ZIP" .
  )

  rm -rf "$TMPDIR"
fi

# 2) S3 bucket
echo "➜ Creating S3 bucket: $S3_BUCKET"
$AWS_CLI s3 mb s3://$S3_BUCKET

# 3) DynamoDB table + TTL
echo "➜ Checking for DynamoDB table: $DDB_TABLE"
if $AWS_CLI dynamodb describe-table --table-name "$DDB_TABLE" > /dev/null 2>&1; then
  echo "⚠️  DynamoDB table '$DDB_TABLE' already exists, skipping creation"
else
  echo "➜ Creating DynamoDB table: $DDB_TABLE"
  $AWS_CLI dynamodb create-table \
    --table-name "$DDB_TABLE" \
    --attribute-definitions AttributeName=jobId,AttributeType=S \
    --key-schema AttributeName=jobId,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST

  echo "➜ Enabling TTL on '$DDB_TABLE'"
  $AWS_CLI dynamodb update-time-to-live \
    --table-name "$DDB_TABLE" \
    --time-to-live-specification "Enabled=true,AttributeName=ttl"
fi

# Ensure TTL is enabled idempotently
$AWS_CLI dynamodb update-time-to-live \
  --table-name "$DDB_TABLE" \
  --time-to-live-specification "Enabled=true,AttributeName=ttl"

# 4) SQS FIFO + DLQ
echo "➜ Creating SQS DLQ (FIFO): $DLQ_NAME"
DLQ_URL=$($AWS_CLI sqs create-queue \
  --queue-name "$DLQ_NAME" \
  --attributes '{"FifoQueue":"true","ContentBasedDeduplication":"true"}' \
  | jq -r .QueueUrl)
DLQ_ARN="arn:aws:sqs:$AWS_REGION:000000000000:$DLQ_NAME"

echo "➜ Creating SQS FIFO queue: $QUEUE_NAME"
$AWS_CLI sqs create-queue \
  --queue-name "$QUEUE_NAME" \
  --attributes '{"FifoQueue":"true","ContentBasedDeduplication":"true","RedrivePolicy":"{\"deadLetterTargetArn\":\"'"$DLQ_ARN"'\",\"maxReceiveCount\":\"3\"}"}'

QUEUE_URL=$($AWS_CLI sqs get-queue-url --queue-name "$QUEUE_NAME" | jq -r .QueueUrl)
echo "   → Queue URL: $QUEUE_URL"

echo "➜ Skipping ECS cluster creation (not supported in OSS LocalStack)"

# 5) Deploy or skip Lambda
echo "➜ Checking for existing Lambda function: $LAMBDA_NAME"
echo "▶️ ZIP package path: $LAMBDA_ZIP"
ls -lh "$LAMBDA_ZIP"
if $AWS_CLI lambda get-function --function-name "$LAMBDA_NAME" > /dev/null 2>&1; then
  echo "⚠️  Lambda function '$LAMBDA_NAME' already exists, skipping creation"
else
  echo "➜ Deploying Lambda function: $LAMBDA_NAME"
  $AWS_CLI lambda create-function \
    --function-name "$LAMBDA_NAME" \
    --runtime python3.9 \
    --handler dispatch_to_ecs.lambda_handler \
    --role arn:aws:iam::000000000000:role/irrelevant \
    --zip-file fileb://"$LAMBDA_ZIP" \
    --timeout 300 \
    --environment "Variables={ECS_CLUSTER=$ECS_CLUSTER,ECS_TASK_DEF=chronicle-recorder-task,S3_BUCKET=$S3_BUCKET,DDB_TABLE=$DDB_TABLE,CONTAINER_NAME=chronicle-recorder,SUBNET_IDS=,SECURITY_GROUP_IDS=,TTL_DAYS=30}"
fi

# 6) API Gateway
echo "➜ Creating API Gateway REST API: $API_NAME"
API_ID=$($AWS_CLI apigateway create-rest-api --name "$API_NAME" | jq -r .id)
ROOT_ID=$($AWS_CLI apigateway get-resources --rest-api-id "$API_ID" \
  | jq -r '.items[] | select(.path=="/") | .id')

echo "➜ Creating /jobs resource"
RESOURCE_ID=$($AWS_CLI apigateway create-resource --rest-api-id "$API_ID" \
  --parent-id "$ROOT_ID" --path-part jobs | jq -r .id)

for METHOD in GET POST; do
  echo "   → Adding method $METHOD"
  $AWS_CLI apigateway put-method \
    --rest-api-id "$API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method "$METHOD" \
    --authorization-type NONE

  echo "   → Integrating $METHOD → Lambda"
  $AWS_CLI apigateway put-integration \
    --rest-api-id "$API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method "$METHOD" \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:$AWS_REGION:lambda:path/2015-03-31/functions/arn:aws:lambda:$AWS_REGION:000000000000:function:$LAMBDA_NAME/invocations"

  echo "   → Granting invoke permission"
  $AWS_CLI lambda add-permission \
    --function-name "$LAMBDA_NAME" \
    --statement-id "apigw-${METHOD}-${API_ID}" \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:$AWS_REGION:000000000000:$API_ID/*/$METHOD/jobs"
done

echo "➜ Deploying API to stage 'local'"
$AWS_CLI apigateway create-deployment --rest-api-id "$API_ID" --stage-name local

# 7) Event source mapping
echo "-> Creating event source mapping for Lambda"
$AWS_CLI lambda create-event-source-mapping \
  --function-name "$LAMBDA_NAME" \
  --batch-size 1 \
  --event-source-arn "arn:aws:sqs:$AWS_REGION:000000000000:$QUEUE_NAME"

echo "✅ LocalStack setup complete!"
echo "▶ S3 Bucket:   $S3_BUCKET"
echo "▶ Queue URL:   $QUEUE_URL"
echo "▶ DynamoDB:    $DDB_TABLE"
echo "▶ Lambda:      $LAMBDA_NAME"
echo "▶ API URL:     $AWS_ENDPOINT_URL/restapis/$API_ID/local/_user_request_"
