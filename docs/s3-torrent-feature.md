# S3 Torrent Creation Feature

This feature automatically creates torrent files for files uploaded to S3 and then uploads the torrent files back to S3.

## How It Works

1. When a file is uploaded to S3, the system automatically creates a torrent file for it.
2. The torrent file is uploaded back to S3 with the same key as the original file plus the `.torrent` extension.
3. Optionally, the system can start a seeding process for the torrent.

## Implementation Details

### Direct Upload Flow (ECS Task)

For files that are uploaded directly by the ECS task in the recording flow:

1. The `entrypoint.sh` script creates the torrent file after uploading the recording to S3.
2. It uses `transmission-create` to generate the torrent file.
3. The torrent file is uploaded to S3 with the same key as the recording file plus the `.torrent` extension.
4. A DynamoDB record is updated with the torrent file information.
5. Optionally, a transmission seeding task is started.

### Lambda Event Flow (S3 Event Notification)

For files that are uploaded to S3 through other means:

1. An S3 event notification triggers a Lambda function when a file is created in the S3 bucket.
2. The Lambda function:
   - Checks if a torrent file already exists for the S3 object.
   - Downloads the file from S3 to a temporary location.
   - Creates a torrent file using `transmission-create` from a custom Lambda layer.
   - Uploads the torrent file back to S3.
   - Updates DynamoDB with the torrent creation status.

## Components

1. **ECS Task Enhancement**: The existing ECS task that uploads recordings to S3 has been enhanced to create and upload torrent files.
2. **S3 Event Lambda**: A new Lambda function that responds to S3 events and creates torrents for new files.
3. **Lambda Layer**: A custom Lambda layer with the transmission-cli tools needed for torrent creation.

## Deployment

### Production Deployment

1. Build the transmission-cli Lambda layer:

   ```bash
   ./util/build-transmission-lambda-layer.sh
   ```

2. Upload the Lambda layer to AWS (keep note of the ARN):

   ```bash
   aws lambda publish-layer-version \
     --layer-name transmission-tools \
     --description "Lambda layer with transmission-cli tools" \
     --compatible-runtimes python3.8 python3.9 \
     --zip-file fileb://terraform/backend/lambda/transmission_tools_layer.zip
   ```

3. Update the Terraform configuration to use your layer ARN.

4. Apply the Terraform configuration:

   ```bash
   cd terraform/backend
   terraform apply
   ```

### Local Development with LocalStack

1. Start LocalStack:

   ```bash
   cd docker/localstack
   docker-compose up -d
   ```

2. Set up the S3 torrent creator Lambda:

   ```bash
   docker/localstack/s3-torrent-lambda-setup.sh
   ```

3. Test by uploading a file to S3:

   ```bash
   # Create a test file
   echo "This is a test file" > test-file.txt
   
   # Upload to S3
   aws --endpoint-url=http://localhost:4566 s3 cp test-file.txt s3://chronicle-recordings-dev/
   
   # Check if torrent was created
   aws --endpoint-url=http://localhost:4566 s3 ls s3://chronicle-recordings-dev/
   ```

## Configuration Options

The torrent creation feature can be configured with the following options:

### ECS Task Configuration

Set these environment variables in the ECS task definition:

- `TRACKERS`: Comma-separated list of BitTorrent trackers (defaults to a set of public trackers)
- `TRANSMISSION_TASK_DEF`: (Optional) The ARN of the transmission ECS task definition for seeding

### Lambda Configuration

Set these environment variables in the Lambda function configuration:

- `S3_BUCKET`: The S3 bucket name to monitor
- `DDB_TABLE`: The DynamoDB table for status tracking
- `TRACKERS`: Comma-separated list of BitTorrent trackers

## Lambda Layer

The Lambda function depends on a custom Lambda layer that provides the `transmission-create` binary. This layer needs to be created separately since it contains native binaries that aren't available in the standard Lambda runtime.

To build this layer:

1. Run the provided script: `./util/build-transmission-lambda-layer.sh`
2. Upload the resulting zip file to AWS Lambda as a layer
3. Associate the layer with the Lambda function

## Testing

To test the torrent creation functionality:

1. Upload a file to S3 through the normal recording process or directly.
2. Verify that a corresponding `.torrent` file is created in the same location.
3. Download the torrent file and verify it can be opened with a BitTorrent client.
4. If using the Transmission client for seeding, check that the torrent is added and seeding.

## Troubleshooting

If torrent files are not being created:

1. Check the Lambda function logs in CloudWatch or LocalStack logs.
2. Verify that the S3 event notifications are properly configured.
3. Ensure the IAM permissions allow the Lambda function to access S3 and DynamoDB.
4. Check that the transmission-cli tools are properly installed in the Lambda layer. 