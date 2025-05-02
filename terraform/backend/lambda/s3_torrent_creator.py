import os
import json
import logging
import time
import urllib.parse
import tempfile
import subprocess
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
    region_name=os.environ.get("AWS_REGION")
)
table = dynamodb.Table(os.environ["DDB_TABLE"])
s3_client = boto3.client(
    "s3",
    region_name=os.environ.get("AWS_REGION")
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
    except Exception as e:
        logger.error(f"Error updating DynamoDB: {e}")

def create_torrent_file(local_file_path, s3_key):
    """Create a torrent file from the downloaded S3 file"""
    torrent_filename = os.path.basename(local_file_path) + '.torrent'
    torrent_path = os.path.join(tempfile.gettempdir(), torrent_filename)
    
    try:
        # Create tracker arguments from comma-separated list
        tracker_args = []
        for tracker in TRACKERS.split(','):
            tracker = tracker.strip()
            if tracker:
                tracker_args.extend(['-t', tracker])
        
        # Create the torrent file using transmission-create
        cmd = [
            'transmission-create',
            '-o', torrent_path,
            '-c', f"File from S3: {s3_key}"
        ]
        cmd.extend(tracker_args)
        cmd.append(local_file_path)
        
        logger.info(f"Running command: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode != 0:
            logger.error(f"Error creating torrent: {result.stderr}")
            return None
        
        logger.info(f"Created torrent file at {torrent_path}")
        return torrent_path
    except Exception as e:
        logger.error(f"Error creating torrent: {e}")
        return None

def lambda_handler(event, context):
    """Lambda handler for S3 event triggers"""
    logger.info(f"START handler; event: {json.dumps(event)}")
    
    # Check if transmission-create is available
    try:
        result = subprocess.run(
            ['transmission-create', '--version'],
            capture_output=True, text=True
        )
        logger.info(f"transmission-create version: {result.stdout.strip()}")
    except Exception as e:
        logger.error(f"transmission-create not available: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps('transmission-create not available')
        }
    
    # Process each record in the event
    for record in event.get('Records', []):
        # Skip if not an S3 event
        if record.get('eventSource') != 'aws:s3':
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
                logger.error(f"Error checking if torrent exists: {e}")
                continue
        
        job_id = f"s3-torrent-{int(time.time())}-{os.path.basename(s3_key)}"
        
        # Create initial record in DynamoDB
        try:
            now = int(time.time())
            table.put_item(Item={
                "jobId": job_id,
                "s3Key": s3_key,
                "s3Bucket": s3_bucket,
                "status": "STARTED",
                "createdAt": now,
                "startedAt": now
            })
        except Exception as e:
            logger.error(f"Error creating DynamoDB record: {e}")
        
        # Download the file from S3
        try:
            file_extension = os.path.splitext(s3_key)[1]
            with tempfile.NamedTemporaryFile(delete=False, suffix=file_extension) as tmp_file:
                local_file_path = tmp_file.name
            
            logger.info(f"Downloading {s3_key} to {local_file_path}")
            update_job_status(job_id, "DOWNLOADING", {"s3_key": s3_key})
            s3_client.download_file(s3_bucket, s3_key, local_file_path)
            
            # Create torrent file
            update_job_status(job_id, "CREATING_TORRENT")
            torrent_path = create_torrent_file(local_file_path, s3_key)
            if not torrent_path:
                update_job_status(job_id, "FAILED", {"error": "Failed to create torrent file"})
                continue
            
            # Upload torrent back to S3
            update_job_status(job_id, "UPLOADING_TORRENT")
            logger.info(f"Uploading torrent to S3: {torrent_s3_key}")
            s3_client.upload_file(torrent_path, s3_bucket, torrent_s3_key)
            
            # Set public read access if needed
            # s3_client.put_object_acl(Bucket=s3_bucket, Key=torrent_s3_key, ACL='public-read')
            
            # Success
            update_job_status(job_id, "COMPLETED", {
                "torrent_s3_key": torrent_s3_key,
                "original_s3_key": s3_key
            })
            logger.info(f"Successfully created and uploaded torrent for {s3_key}")
            
        except Exception as e:
            logger.error(f"Error processing {s3_key}: {e}")
            update_job_status(job_id, "FAILED", {"error": str(e)})
        finally:
            # Clean up temporary files
            if 'local_file_path' in locals() and os.path.exists(local_file_path):
                os.unlink(local_file_path)
            if 'torrent_path' in locals() and torrent_path and os.path.exists(torrent_path):
                os.unlink(torrent_path)
    
    return {
        'statusCode': 200,
        'body': json.dumps('Torrent creation completed')
    } 