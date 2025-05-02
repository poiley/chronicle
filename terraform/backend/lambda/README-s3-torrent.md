# S3 Torrent Creator Lambda

This Lambda function automatically creates torrent files for objects uploaded to an S3 bucket.

## Requirements

The Lambda function requires the `transmission-cli` tools to create torrent files. Since this binary and its dependencies are not available in the standard Lambda runtime, we use a custom Lambda layer.

## Lambda Layer Setup

The Lambda layer contains the `transmission-create` binary and its dependencies. To build this layer:

1. Run the build script:
   ```bash
   ./util/build-transmission-lambda-layer.sh
   ```

2. This will create a Lambda layer zip file at `terraform/backend/lambda/transmission_tools_layer.zip`.

3. In production, you should upload this layer to AWS Lambda either manually or via CI/CD:
   ```bash
   aws lambda publish-layer-version \
     --layer-name transmission-tools \
     --description "Lambda layer with transmission-cli tools" \
     --compatible-runtimes python3.8 python3.9 \
     --zip-file fileb://terraform/backend/lambda/transmission_tools_layer.zip
   ```

4. After uploading, note the ARN of the layer and update the Terraform configuration.

## Tracker Configuration

The system is configured to use your own BitTorrent tracker (opentracker) instead of public trackers. This is controlled in several places:

1. **Dynamic IP Configuration**: Use the `util/track-ip-config.sh` script to automatically configure all components with the actual public IP of your opentracker instance
2. **Configuration File**: `terraform/backend/lambda/tracker-config.json` contains the tracker URL
3. **Lambda Environment**: The `TRACKERS` environment variable is set in Terraform and LocalStack setup
4. **ECS Entrypoint**: Used in the transmission-create command in entrypoint.sh script

To update the tracker configuration:

1. Start your opentracker instance
2. Run the configuration script:
   ```bash
   chmod +x util/track-ip-config.sh
   ./util/track-ip-config.sh
   ```
3. This will automatically detect your opentracker's public IP and update all configuration files

For manual configuration, update:
- `tracker-config.json` - Contains primary tracker URL
- The `--environment` parameter in `docker/localstack/s3-torrent-lambda-setup.sh`
- The `transmission-create` command in `docker/ecs/entrypoint.sh`
- The `TRACKERS` variable in `terraform/backend/s3-torrent-lambda.tf`

IMPORTANT: Never use public trackers as these would expose your files publicly. Always use your own opentracker instance.

## Lambda Function

The Lambda function is triggered by S3 `ObjectCreated` events. When triggered, it:

1. Downloads the S3 object to a temporary location
2. Creates a torrent file using `transmission-create`
3. Uploads the torrent file to a "watch" subfolder in S3 (key format: `watch/filename.ext.torrent`)
4. Updates status in DynamoDB

The "watch" folder is a dedicated location in the S3 bucket used to store torrent files, making it easier for downstream processing (like Transmission) to find and use them.

## Development and Testing

For local testing:

1. Use the improved LocalStack setup script that handles resource conflicts and Docker networking:
   ```bash
   docker/localstack/s3-torrent-lambda-setup.sh
   ```

2. Or use the full rebuild script that gracefully handles errors:
   ```bash
   ./util/rebuild_images_no_cache.sh
   ```

3. Upload a test file to the S3 bucket:
   ```bash
   aws --endpoint-url=http://localhost:4566 s3 cp test-file.txt s3://chronicle-recordings-dev/
   ```

4. Check if the torrent was created:
   ```bash
   aws --endpoint-url=http://localhost:4566 s3 ls s3://chronicle-recordings-dev/
   ```

## Configuration

The Lambda function can be configured with the following environment variables:

- `S3_BUCKET`: (Optional) The S3 bucket to monitor. If not specified, it will use the bucket from the event.
- `DDB_TABLE`: The DynamoDB table for status tracking.
- `TRACKERS`: Comma-separated list of BitTorrent trackers.
- `AWS_ENDPOINT_URL`: LocalStack endpoint URL. For local development, this is automatically set to the Docker network IP.

## Terraform Integration

The Lambda function and its resources are defined in `terraform/backend/s3-torrent-lambda.tf`.

In a development environment, it will create a placeholder Lambda layer. In production, you should:

1. Build and publish the layer manually
2. Update the Terraform configuration with the ARN of the published layer

## Recent Improvements

The following improvements have been made to the system:

1. **Robust Error Handling**: All scripts now handle errors and resource conflicts gracefully.
   - Continue even when resources already exist
   - Detailed error reporting for debugging
   - No abrupt script termination on non-critical errors

2. **Docker Network Connectivity**: For LocalStack development:
   - Automatically detects the Docker network IP of LocalStack
   - Configures Lambda to connect to LocalStack properly from inside the Lambda container
   - Avoids "endpoint connection errors" in local testing

3. **DynamoDB Auto-creation**: The Lambda function now checks for and creates the DynamoDB table if missing.

4. **Race Condition Handling**: Added extra checks to avoid issues when multiple processes try to create the same torrent.

5. **Custom Tracker Support**: Updated to use your own opentracker instance rather than public trackers.

## Two Torrent Creation Paths

The system now has two ways to create torrents:

1. **Direct Path**: During recording via the ECS task's `entrypoint.sh` script
2. **Event-Based Path**: Through S3 notifications for files uploaded through any means

## Troubleshooting

Common issues:

1. **Missing transmission-create binary**: Ensure the Lambda layer is properly created and attached.
2. **Permission issues**: Check the IAM role has the necessary permissions for S3 and DynamoDB.
3. **Lambda timeout**: If processing large files, increase the Lambda timeout and memory allocation.
4. **Missing S3 notifications**: Verify that the S3 bucket notifications are properly configured.
5. **LocalStack connectivity**: If the Lambda can't connect to LocalStack, check that the Docker network IP is correctly detected.
6. **Resource conflicts**: If you see errors about resources already existing, the script should handle this gracefully now. If issues persist, manually clean up resources before retrying.
7. **Tracker connectivity**: Ensure your opentracker instance is accessible from both the Lambda function and the ECS task. 