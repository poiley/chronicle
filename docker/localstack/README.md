# LocalStack Development Environment

This directory contains the LocalStack setup for local development and testing. LocalStack provides a fully functional local AWS cloud stack that allows us to develop and test AWS-dependent features without incurring AWS costs.

## Services Emulated

- S3: Object storage
- SQS: Message queuing
- DynamoDB: NoSQL database
- Lambda: Serverless functions
- API Gateway: REST API endpoints
- CloudWatch Logs: Logging

## Quick Start

1. Start LocalStack:
   ```bash
   docker-compose up -d
   ```

2. Run the initial setup script:
   ```bash
   ./localstack_setup.sh
   ```

3. Set up the S3 torrent creation feature:
   ```bash
   ./torrent_lambda_setup.sh
   ```

## Configuration

### Environment Variables

The LocalStack container is configured with:
- `SERVICES`: Enabled AWS services
- `DEBUG`: Debug mode for verbose logging
- `AWS_ACCESS_KEY_ID`: Test credentials (always "test")
- `AWS_SECRET_ACCESS_KEY`: Test credentials (always "test")
- `AWS_DEFAULT_REGION`: Default AWS region (us-west-1)
- `LAMBDA_EXECUTOR`: Lambda execution mode (docker)

### Volumes

- `localstack_data`: Persistent data storage
- `/var/run/docker.sock`: Docker socket for Lambda execution

## Setup Scripts

### localstack_setup.sh

Sets up the core infrastructure:
1. Creates S3 bucket for recordings
2. Creates DynamoDB table for job tracking
3. Sets up SQS FIFO queue with DLQ
4. Deploys dispatch Lambda function
5. Configures API Gateway endpoints
6. Sets up CORS

### torrent_lambda_setup.sh

Configures the torrent creation system:
1. Creates S3 bucket if not exists
2. Sets up watch folder
3. Deploys torrent creator Lambda
4. Configures S3 event triggers
5. Sets up necessary permissions

## Testing

### Test API Gateway

```bash
# List jobs
curl http://localhost:4566/restapis/[API_ID]/test/_user_request_/jobs

# Create job
curl -X POST http://localhost:4566/restapis/[API_ID]/test/_user_request_/jobs \
  -H "Content-Type: application/json" \
  -d '{"url": "test-url"}'
```

### Test S3 Upload

```bash
# Create test file
echo "test content" > test.txt

# Upload to S3
aws --endpoint-url=http://localhost:4566 s3 cp test.txt s3://chronicle-recordings-dev/

# List bucket contents
aws --endpoint-url=http://localhost:4566 s3 ls s3://chronicle-recordings-dev/
```

### Test Lambda Functions

```bash
# Invoke dispatch Lambda
aws --endpoint-url=http://localhost:4566 lambda invoke \
  --function-name dispatch-to-ecs \
  --payload '{"jobId": "test-123"}' \
  output.json

# Check Lambda logs
aws --endpoint-url=http://localhost:4566 logs tail /aws/lambda/dispatch-to-ecs
```

## Troubleshooting

1. **Services Not Starting**
   - Check Docker logs: `docker logs chronicle-localstack`
   - Ensure ports are not in use
   - Verify Docker socket mounting

2. **Lambda Issues**
   - Check Lambda logs in CloudWatch
   - Verify Lambda has correct permissions
   - Ensure Docker socket is properly mounted

3. **S3 Event Triggers**
   - Verify bucket notification configuration
   - Check Lambda permissions for S3
   - Monitor CloudWatch logs for trigger events

4. **API Gateway**
   - Test endpoints directly against LocalStack
   - Check CORS configuration
   - Verify Lambda integration 