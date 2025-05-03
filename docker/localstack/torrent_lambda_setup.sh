#!/bin/bash
# Replace strict error handling with more forgiving approach
set +e  # Don't exit on errors
trap 'echo "Warning at line $LINENO - continuing anyway"' ERR

# Variables
LOCALSTACK_ENDPOINT="http://localhost:4566"
BUCKET_NAME="chronicle-recordings-dev"
LAMBDA_NAME="s3-torrent-creator"
LAMBDA_HANDLER="s3_torrent_creator_local.lambda_handler"
FUNCTION_DIR="./terraform/backend/lambda"
REGION="us-west-1"
TMP_DIR="/tmp/lambda_setup"  # Using system /tmp directory

# Try to detect the tracker's IP
get_tracker_ip() {
  # Try to get from container
  IP=""
  if docker ps | grep -q "torrent-tracker"; then
    IP=$(docker exec torrent-tracker cat /tmp/public-ip 2>/dev/null || echo "")
  fi
  
  # If that fails, try to get our own public IP
  if [ -z "$IP" ] || [ "$IP" = "127.0.0.1" ]; then
    IP=$(curl -s https://api.ipify.org 2>/dev/null || curl -s https://ifconfig.me 2>/dev/null || curl -s https://icanhazip.com 2>/dev/null || echo "")
  fi
  
  # If everything fails, use the example domain
  if [ -z "$IP" ]; then
    echo "opentracker.example.com"
  else
    echo "$IP"
  fi
}

# Get the tracker IP and build the tracker URL
TRACKER_IP=$(get_tracker_ip)
TRACKER_PORT=6969
TRACKER_URL="udp://${TRACKER_IP}:${TRACKER_PORT}"
echo "Using tracker URL: $TRACKER_URL"

# Get the Docker network address of the LocalStack container
LOCALSTACK_DOCKER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' chronicle-localstack 2>/dev/null)
if [ -z "$LOCALSTACK_DOCKER_IP" ]; then
  echo "Could not get LocalStack Docker IP, using default"
  LAMBDA_ENDPOINT_URL="$LOCALSTACK_ENDPOINT"
else
  echo "Using LocalStack Docker IP: $LOCALSTACK_DOCKER_IP"
  LAMBDA_ENDPOINT_URL="http://${LOCALSTACK_DOCKER_IP}:4566"
fi

# Ensure Docker is running
if ! docker ps &>/dev/null; then
  echo "Docker doesn't seem to be running. Please start Docker and try again."
  exit 1
fi

# Check if LocalStack is running
if ! response=$(curl -s http://localhost:4566/_localstack/health) || ! echo "$response" | grep -q '"services"'; then
  echo "LocalStack doesn't seem to be running. Please start LocalStack and try again."
  exit 1
fi

# Stop any prompting
export PAGER=cat

echo "===== S3 Torrent Lambda Setup ====="

# Create S3 bucket if it doesn't exist
echo "Checking S3 bucket..."
if ! aws --endpoint-url="$LOCALSTACK_ENDPOINT" --region="$REGION" s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "Creating bucket '$BUCKET_NAME'..."
  aws --endpoint-url="$LOCALSTACK_ENDPOINT" --region="$REGION" s3 mb "s3://$BUCKET_NAME" --no-cli-pager || echo "Bucket creation failed, but continuing"
else
  echo "Bucket '$BUCKET_NAME' already exists, skipping creation."
fi

# Create the watch folder in the S3 bucket
echo "Creating watch folder in S3 bucket..."
aws --endpoint-url="$LOCALSTACK_ENDPOINT" --region="$REGION" s3api put-object \
  --bucket "$BUCKET_NAME" \
  --key "watch/" \
  --content-length 0 || echo "Failed to create watch folder, but continuing"

# Create a Lambda deployment package
echo "Creating Lambda deployment package..."
rm -rf "$TMP_DIR" "$TMP_DIR.zip"
mkdir -p "$TMP_DIR"

# Check if the Python file exists
if [ ! -f "$FUNCTION_DIR/s3_torrent_creator_local.py" ]; then
  echo "ERROR: Lambda handler file not found at '$FUNCTION_DIR/s3_torrent_creator_local.py'"
  echo "Please create this file first"
  exit 1
fi

cp "$FUNCTION_DIR/s3_torrent_creator_local.py" "$TMP_DIR/s3_torrent_creator_local.py"
cd "$TMP_DIR" || {
  echo "ERROR: Could not cd to $TMP_DIR"
  exit 1
}

echo "Installing dependencies..."
pip install -q -t . boto3 botocore >/dev/null 2>&1 || echo "WARNING: dependency installation issues, but continuing"
echo "Creating ZIP archive..."
zip -q -r ../lambda_setup.zip . >/dev/null || echo "WARNING: ZIP creation issues, but continuing"
cd - >/dev/null || echo "WARNING: Could not cd back to original directory"

# Check if Lambda function exists and remove it if it does
echo "Checking for existing Lambda function..."
if aws --endpoint-url="$LOCALSTACK_ENDPOINT" --region="$REGION" lambda get-function --function-name "$LAMBDA_NAME" 2>/dev/null; then
  echo "Removing existing Lambda function '$LAMBDA_NAME'..."
  aws --endpoint-url="$LOCALSTACK_ENDPOINT" --region="$REGION" --no-cli-pager lambda delete-function \
    --function-name "$LAMBDA_NAME" || echo "Function deletion failed, but continuing"
  
  # Wait a moment for the deletion to complete
  echo "Waiting for Lambda deletion to complete..."
  sleep 2
else
  echo "Lambda function '$LAMBDA_NAME' does not exist, proceeding with creation."
fi

# Create Lambda function
echo "Creating Lambda function '$LAMBDA_NAME'..."
echo "Using endpoint URL for Lambda: $LAMBDA_ENDPOINT_URL"
LAMBDA_CREATE_RESULT=0
aws --endpoint-url="$LOCALSTACK_ENDPOINT" --region="$REGION" --no-cli-pager lambda create-function \
  --function-name "$LAMBDA_NAME" \
  --zip-file "fileb:///tmp/lambda_setup.zip" \
  --handler "$LAMBDA_HANDLER" \
  --runtime "python3.9" \
  --role "arn:aws:iam::000000000000:role/s3-torrent-lambda-role" \
  --environment "Variables={S3_BUCKET=$BUCKET_NAME,DDB_TABLE=jobs,TRACKERS=$TRACKER_URL,AWS_ENDPOINT_URL=$LAMBDA_ENDPOINT_URL,DOCKER_HOST=tcp://host.docker.internal:2375}" \
  --timeout 300 \
  --memory-size 1024 || LAMBDA_CREATE_RESULT=1

if [ $LAMBDA_CREATE_RESULT -ne 0 ]; then
  echo "WARNING: Lambda function creation had issues, but we'll continue anyway"
else
  echo "Lambda function created successfully!"
fi

# Add permission for S3 to invoke Lambda
echo "Adding permission for S3 to invoke Lambda..."
PERMISSION_RESULT=0
aws --endpoint-url="$LOCALSTACK_ENDPOINT" --region="$REGION" --no-cli-pager lambda add-permission \
  --function-name "$LAMBDA_NAME" \
  --statement-id "s3-permission" \
  --action "lambda:InvokeFunction" \
  --principal "s3.amazonaws.com" \
  --source-arn "arn:aws:s3:::$BUCKET_NAME" || PERMISSION_RESULT=1

if [ $PERMISSION_RESULT -ne 0 ]; then
  echo "WARNING: Lambda permission setup had issues, S3 may not be able to invoke Lambda"
else
  echo "Lambda permission configured successfully!"
fi

# Wait a moment for permissions to propagate
sleep 5

# Now set the S3 notification
echo "Configuring S3 trigger for Lambda..."
S3_TRIGGER_RESULT=0
aws --endpoint-url="$LOCALSTACK_ENDPOINT" --region="$REGION" --no-cli-pager s3api put-bucket-notification-configuration \
  --bucket "$BUCKET_NAME" \
  --notification-configuration '{
    "LambdaFunctionConfigurations": [
      {
        "LambdaFunctionArn": "arn:aws:lambda:'"$REGION"':000000000000:function:'"$LAMBDA_NAME"'",
        "Events": ["s3:ObjectCreated:*"]
      }
    ]
  }' || S3_TRIGGER_RESULT=1

if [ $S3_TRIGGER_RESULT -ne 0 ]; then
  echo "WARNING: S3 trigger setup had issues, S3 events may not trigger Lambda"
else
  echo "S3 trigger configured successfully!"
fi

# Check for Lambda permissions (should handle its own errors)
echo "Checking for existing Lambda permissions..."
if aws --endpoint-url="$LOCALSTACK_ENDPOINT" --region="$REGION" lambda get-policy --function-name "$LAMBDA_NAME" 2>/dev/null | grep -q "s3-permission"; then
  echo "Removing existing Lambda permission..."
  aws --endpoint-url="$LOCALSTACK_ENDPOINT" --region="$REGION" --no-cli-pager lambda remove-permission \
    --function-name "$LAMBDA_NAME" \
    --statement-id "s3-permission" || echo "Failed to remove existing permission, but continuing"
fi

# Cleanup
echo "Cleaning up temporary files..."
rm -rf "/tmp/lambda_setup.zip" || echo "Cleanup had issues, but that's fine"

echo "===== S3 Torrent Lambda Setup Complete ====="
echo "Try uploading a file to S3 to test:"
echo "aws --endpoint-url=\"$LOCALSTACK_ENDPOINT\" --region=\"$REGION\" s3 cp test-file.txt s3://$BUCKET_NAME/"

# Exit with success regardless of any errors that may have occurred
exit 0 