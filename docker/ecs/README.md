# ECS Container Configuration

This directory contains the Docker configuration for the Chronicle recorder container that runs in ECS Fargate. The container is responsible for recording livestreams and uploading them to S3.

## Components

### Dockerfile

The Dockerfile sets up a container with:
- Python 3.9 runtime
- yt-dlp for stream recording
- AWS CLI for S3 uploads
- transmission-cli for torrent creation
- Required system dependencies

### entrypoint.sh

The entrypoint script handles:
1. Stream recording with yt-dlp
2. S3 upload of recordings
3. Torrent file creation
4. DynamoDB status updates
5. Error handling and cleanup

## Configuration

### Environment Variables

The container requires:
- `AWS_ACCESS_KEY_ID`: AWS credentials
- `AWS_SECRET_ACCESS_KEY`: AWS credentials
- `AWS_DEFAULT_REGION`: AWS region
- `S3_BUCKET`: Target S3 bucket
- `DDB_TABLE`: DynamoDB table name
- `JOB_ID`: Unique job identifier
- `URL`: Stream URL to record
- `FILENAME`: Output filename
- `TRACKERS`: BitTorrent tracker URLs

### Resource Requirements

Default resource allocation:
- CPU: 1 vCPU
- Memory: 2GB
- Storage: 20GB

## Local Development

1. Build the container:
   ```bash
   docker build -t chronicle-recorder .
   ```

2. Run with LocalStack:
   ```bash
   docker run -e AWS_ENDPOINT_URL=http://localhost:4566 \
     -e AWS_ACCESS_KEY_ID=test \
     -e AWS_SECRET_ACCESS_KEY=test \
     -e AWS_DEFAULT_REGION=us-west-1 \
     -e S3_BUCKET=chronicle-recordings-dev \
     -e DDB_TABLE=jobs \
     -e JOB_ID=test-123 \
     -e URL=https://example.com/stream \
     -e FILENAME=test-recording.mkv \
     -e TRACKERS=udp://tracker.example.com:6969 \
     chronicle-recorder
   ```

## Production Deployment

The container is deployed via Terraform in `terraform/backend/ecs.tf`. Key configurations:

- Task Definition:
  - Fargate launch type
  - Required IAM roles
  - CloudWatch logging
  - Resource allocations

- Service Configuration:
  - Desired count
  - Security groups
  - Subnet placement
  - Auto-scaling rules

## Error Handling

The container implements robust error handling:

1. **Pre-flight Checks**
   - Validates environment variables
   - Checks AWS credentials
   - Verifies URL accessibility

2. **Recording**
   - Monitors yt-dlp progress
   - Handles stream interruptions
   - Manages disk space

3. **Upload**
   - Implements multipart upload
   - Handles network issues
   - Verifies upload completion

4. **Status Updates**
   - Real-time progress reporting
   - Error state management
   - Cleanup on failure

## Monitoring

The container outputs structured logs to CloudWatch with:
- Recording progress
- Upload status
- Error details
- Resource usage

## Related Components

- [Lambda Functions](../../terraform/backend/lambda/README.md)
- [Transmission Container](../transmission/README.md)
- [LocalStack Setup](../localstack/README.md) 