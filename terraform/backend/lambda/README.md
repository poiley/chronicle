# Lambda Functions

This directory contains the Lambda functions used in the Chronicle system. There are two main Lambda functions:

1. **Dispatch to ECS** (`dispatch_to_ecs.py`): Handles job requests and launches ECS tasks
2. **S3 Torrent Creator** (`s3_torrent_creator.py`): Creates torrent files for S3 uploads

For the S3 torrent creator documentation, see [README-s3-torrent.md](README-s3-torrent.md).

## Dispatch to ECS Lambda

The dispatch Lambda function is triggered by:
- API Gateway requests (REST API)
- SQS messages (job queue)

### Configuration

Environment variables:
- `ECS_CLUSTER`: ECS cluster name
- `ECS_TASK_DEF`: ECS task definition ARN
- `S3_BUCKET`: Target S3 bucket for recordings
- `DDB_TABLE`: DynamoDB table for job tracking
- `CONTAINER_NAME`: ECS container name
- `TTL_DAYS`: DynamoDB record TTL in days
- `TRANSMISSION_TASK_DEF`: Transmission ECS task definition

### Local Development

1. Start LocalStack:
   ```bash
   cd docker/localstack
   docker-compose up -d
   ```

2. Run the setup script:
   ```bash
   ./localstack_setup.sh
   ```

3. Test the function:
   ```bash
   # Via API Gateway
   curl -X POST http://localhost:4566/restapis/[API_ID]/test/_user_request_/jobs \
     -H "Content-Type: application/json" \
     -d '{"url": "https://example.com/stream"}'

   # Direct Lambda invocation
   aws --endpoint-url=http://localhost:4566 lambda invoke \
     --function-name dispatch-to-ecs \
     --payload '{"url": "https://example.com/stream"}' \
     output.json
   ```

### Deployment

The function is deployed via Terraform in `terraform/backend/lambda.tf`. Key configurations:

- IAM role with permissions for:
  - ECS task launching
  - DynamoDB access
  - SQS message processing
  - CloudWatch logging

- Function settings:
  - Memory: 128 MB
  - Timeout: 30 seconds
  - Runtime: Python 3.9

### Error Handling

The function implements robust error handling:

1. **Input Validation**
   - Validates URL format
   - Checks for required parameters
   - Sanitizes input data

2. **ECS Task Launch**
   - Retries on transient failures
   - Handles capacity issues
   - Reports detailed error messages

3. **DynamoDB Updates**
   - Uses conditional writes
   - Handles throttling
   - Implements retry logic

4. **SQS Processing**
   - Handles partial batch failures
   - Implements dead-letter queue
   - Manages message visibility

### Monitoring

The function emits CloudWatch metrics for:
- Invocation count
- Error rate
- Duration
- Throttling
- ECS task launch success/failure

### Related Components

- [LocalStack Setup](../../docker/localstack/README.md)
- [ECS Task Definition](../../docker/ecs/README.md)
- [DynamoDB Schema](../dynamodb.tf)
- [API Gateway Configuration](../api.tf)
