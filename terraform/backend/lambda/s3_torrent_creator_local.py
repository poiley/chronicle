import os
import json
import logging
import time
import urllib.parse
import tempfile
import boto3
from botocore.exceptions import ClientError

# Configure root logger
logger = logging.getLogger()
logger.setLevel(logging.INFO)
handler = logging.StreamHandler()
formatter = logging.Formatter(
    '%(asctime)s %(levelname)s [%(funcName)s] %(message)s'
)
handler.setFormatter(formatter)
logger.addHandler(handler)

# Environment variables
TRACKERS = os.environ.get('TRACKERS', 'udp://tracker.opentrackr.org:1337,udp://open.demonii.com:1337,udp://tracker.openbittorrent.com:80')
s3_bucket_name = os.environ.get('S3_BUCKET')

# Initialize AWS clients
dynamodb = boto3.resource(
    "dynamodb",
    region_name=os.environ.get("AWS_REGION", "us-west-1"),
    endpoint_url=os.environ.get("AWS_ENDPOINT_URL", "http://localhost:4566")
)
table = dynamodb.Table(os.environ.get("DDB_TABLE", "jobs"))
s3_client = boto3.client(
    "s3",
    region_name=os.environ.get("AWS_REGION", "us-west-1"),
    endpoint_url=os.environ.get("AWS_ENDPOINT_URL", "http://localhost:4566")
)

def update_job_status(job_id, status, details=None):
    """Update DynamoDB with torrent creation status"""
    try:
        update_expression = "SET #status = :status, lastUpdatedAt = :time"
        expression_attr_names = {"#status": "status"}
        expression_attr_values = {
            ":status": status,
            ":time": int(time.time())
        }
        
        if details:
            update_expression += ", details = :details"
            expression_attr_values[":details"] = json.dumps(details)

        table.update_item(
            Key={"jobId": job_id},
            UpdateExpression=update_expression,
            ExpressionAttributeNames=expression_attr_names,
            ExpressionAttributeValues=expression_attr_values
        )
        logger.info(f"Updated job {job_id} status to {status}")
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        logger.error(f"DynamoDB error updating job status: {error_code} - {error_message}")
    except Exception as e:
        logger.error(f"Error updating DynamoDB: {str(e)}")

def create_torrent_file_mock(local_file_path, s3_key):
    """Mock creating a torrent file (for LocalStack testing only)"""
    torrent_filename = os.path.basename(local_file_path) + '.torrent'
    torrent_path = os.path.join(tempfile.gettempdir(), torrent_filename)
    
    try:
        # Create a simple mock torrent file 
        with open(torrent_path, 'w') as f:
            f.write(f"d8:announce{len(TRACKERS.split(',')[0])}:{TRACKERS.split(',')[0]}10:created by16:Chronicle Torrent4:infod6:lengthi{os.path.getsize(local_file_path)}e4:name{len(os.path.basename(local_file_path))}:{os.path.basename(local_file_path)}12:piece lengthi16384eee")
        
        logger.info(f"Created mock torrent file at {torrent_path}")
        return torrent_path
    except Exception as e:
        logger.error(f"Error creating mock torrent file: {str(e)}")
        return None

def check_dynamodb_table():
    """Verify DynamoDB table exists and create it if missing"""
    table_name = os.environ.get("DDB_TABLE", "jobs")
    try:
        # Check if table exists
        dynamodb.meta.client.describe_table(TableName=table_name)
        logger.info(f"DynamoDB table {table_name} exists")
        return True
    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceNotFoundException':
            logger.warning(f"DynamoDB table {table_name} not found, creating...")
            try:
                # Create table if it doesn't exist
                table = dynamodb.create_table(
                    TableName=table_name,
                    KeySchema=[
                        {'AttributeName': 'jobId', 'KeyType': 'HASH'}
                    ],
                    AttributeDefinitions=[
                        {'AttributeName': 'jobId', 'AttributeType': 'S'}
                    ],
                    ProvisionedThroughput={'ReadCapacityUnits': 5, 'WriteCapacityUnits': 5}
                )
                table.meta.client.get_waiter('table_exists').wait(TableName=table_name)
                logger.info(f"Created DynamoDB table {table_name}")
                return True
            except Exception as create_error:
                logger.error(f"Failed to create DynamoDB table: {str(create_error)}")
                return False
        else:
            logger.error(f"Error checking DynamoDB table: {e.response['Error']['Code']} - {e.response['Error']['Message']}")
            return False

def lambda_handler(event, context):
    """Lambda handler for S3 event triggers"""
    logger.info(f"START handler; event: {json.dumps(event)}")
    
    # Make sure DynamoDB table exists
    if not check_dynamodb_table():
        logger.error("Cannot proceed without DynamoDB table")
        return {
            'statusCode': 500,
            'body': json.dumps('Failed to verify DynamoDB table')
        }
    
    # Process each record in the event
    for record in event.get('Records', []):
        # Skip if not an S3 event
        if record.get('eventSource') != 'aws:s3':
            logger.info(f"Skipping non-S3 event: {record.get('eventSource')}")
            continue
            
        # Get S3 bucket and key
        s3_bucket = record['s3']['bucket']['name']
        s3_key = urllib.parse.unquote_plus(record['s3']['object']['key'])
        
        # Skip torrent files
        if s3_key.endswith('.torrent'):
            logger.info(f"Skipping torrent file: {s3_key}")
            continue
            
        # Skip if torrent already exists
        torrent_s3_key = s3_key + '.torrent'
        try:
            s3_client.head_object(Bucket=s3_bucket, Key=torrent_s3_key)
            logger.info(f"Torrent already exists for {s3_key}, skipping")
            continue
        except ClientError as e:
            if e.response['Error']['Code'] != '404':
                logger.error(f"Error checking if torrent exists: {e.response['Error']['Code']} - {e.response['Error']['Message']}")
                continue
        
        job_id = f"s3-torrent-{int(time.time())}-{os.path.basename(s3_key)}"
        
        # Create initial record in DynamoDB
        try:
            now = int(time.time())
            
            # Check if job already exists
            try:
                response = table.get_item(Key={"jobId": job_id})
                if 'Item' in response:
                    logger.info(f"Job {job_id} already exists, skipping creation")
                    continue
            except ClientError as e:
                if e.response['Error']['Code'] != 'ResourceNotFoundException':
                    logger.error(f"Error checking job existence: {e.response['Error']['Code']} - {e.response['Error']['Message']}")
                    continue
            
            # Create the job record
            table.put_item(Item={
                "jobId": job_id,
                "s3Key": s3_key,
                "s3Bucket": s3_bucket,
                "status": "STARTED",
                "createdAt": now,
                "startedAt": now
            })
            logger.info(f"Created job record {job_id} for {s3_key}")
        except ClientError as e:
            logger.error(f"DynamoDB error creating job: {e.response['Error']['Code']} - {e.response['Error']['Message']}")
            continue
        except Exception as e:
            logger.error(f"Error creating DynamoDB record: {str(e)}")
            continue
        
        # Download the file from S3
        local_file_path = None
        torrent_path = None
        
        try:
            file_extension = os.path.splitext(s3_key)[1]
            with tempfile.NamedTemporaryFile(delete=False, suffix=file_extension) as tmp_file:
                local_file_path = tmp_file.name
            
            logger.info(f"Downloading {s3_key} to {local_file_path}")
            update_job_status(job_id, "DOWNLOADING", {"s3_key": s3_key})
            
            try:
                s3_client.download_file(s3_bucket, s3_key, local_file_path)
            except ClientError as e:
                error_msg = f"S3 download error: {e.response['Error']['Code']} - {e.response['Error']['Message']}"
                logger.error(error_msg)
                update_job_status(job_id, "FAILED", {"error": error_msg})
                continue
            
            # Check if file was downloaded successfully
            if not os.path.exists(local_file_path) or os.path.getsize(local_file_path) == 0:
                error_msg = f"Downloaded file is empty or missing: {local_file_path}"
                logger.error(error_msg)
                update_job_status(job_id, "FAILED", {"error": error_msg})
                continue
            
            # Create mock torrent file (for LocalStack testing)
            update_job_status(job_id, "CREATING_TORRENT")
            torrent_path = create_torrent_file_mock(local_file_path, s3_key)
            if not torrent_path:
                update_job_status(job_id, "FAILED", {"error": "Failed to create torrent file"})
                continue
            
            # Check if torrent file was created successfully
            if not os.path.exists(torrent_path) or os.path.getsize(torrent_path) == 0:
                error_msg = "Generated torrent file is empty or missing"
                logger.error(error_msg)
                update_job_status(job_id, "FAILED", {"error": error_msg})
                continue
            
            # Upload torrent back to S3
            update_job_status(job_id, "UPLOADING_TORRENT")
            logger.info(f"Uploading torrent to S3: {torrent_s3_key}")
            
            try:
                # Check one more time if torrent already exists (race condition check)
                try:
                    s3_client.head_object(Bucket=s3_bucket, Key=torrent_s3_key)
                    logger.info(f"Torrent now exists for {s3_key} (created by another process), skipping upload")
                    update_job_status(job_id, "COMPLETED", {
                        "torrent_s3_key": torrent_s3_key,
                        "original_s3_key": s3_key,
                        "note": "Torrent already exists, skipped upload"
                    })
                    continue
                except ClientError as e:
                    if e.response['Error']['Code'] != '404':
                        error_msg = f"Error checking if torrent exists before upload: {e.response['Error']['Code']} - {e.response['Error']['Message']}"
                        logger.error(error_msg)
                        update_job_status(job_id, "FAILED", {"error": error_msg})
                        continue
                
                # Upload the torrent file
                s3_client.upload_file(torrent_path, s3_bucket, torrent_s3_key)
            except ClientError as e:
                error_msg = f"S3 upload error: {e.response['Error']['Code']} - {e.response['Error']['Message']}"
                logger.error(error_msg)
                update_job_status(job_id, "FAILED", {"error": error_msg})
                continue
            
            # Success
            update_job_status(job_id, "COMPLETED", {
                "torrent_s3_key": torrent_s3_key,
                "original_s3_key": s3_key
            })
            logger.info(f"Successfully created and uploaded torrent for {s3_key}")
            
        except Exception as e:
            logger.error(f"Error processing {s3_key}: {str(e)}")
            update_job_status(job_id, "FAILED", {"error": str(e)})
        finally:
            # Clean up temporary files
            try:
                if local_file_path and os.path.exists(local_file_path):
                    os.unlink(local_file_path)
                    logger.debug(f"Removed temporary file: {local_file_path}")
                
                if torrent_path and os.path.exists(torrent_path):
                    os.unlink(torrent_path)
                    logger.debug(f"Removed temporary torrent file: {torrent_path}")
            except Exception as cleanup_error:
                logger.warning(f"Error cleaning up temporary files: {str(cleanup_error)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps('Torrent creation completed')
    } 