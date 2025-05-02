import os
import json
import logging
import time
import datetime
import boto3

# Configure root logger
logger = logging.getLogger()
logger.setLevel(logging.INFO)
handler = logging.StreamHandler()
formatter = logging.Formatter(
    '%(asctime)s %(levelname)s [%(funcName)s] %(message)s'
)
handler.setFormatter(formatter)
logger.addHandler(handler)

# Initialize AWS clients
dynamodb = boto3.resource(
    "dynamodb",
    region_name=os.environ.get("AWS_REGION")
)
table = dynamodb.Table(os.environ["DDB_TABLE"])
s3 = boto3.client(
    "s3",
    region_name=os.environ.get("AWS_REGION")
)

ecs_cluster    = os.environ.get("ECS_CLUSTER")
ecs_task_def   = os.environ.get("ECS_TASK_DEF")
container_name = os.environ.get("CONTAINER_NAME")
s3_bucket      = os.environ.get("S3_BUCKET")
ttl_days       = int(os.environ.get("TTL_DAYS", "30"))


def lambda_handler(event, context):
    # Check if event is from API Gateway
    if event.get('httpMethod'):
        return handle_api_request(event, context)
    # Otherwise handle SQS event as before
    
    # startup log
    logger.info("START handler; event: %s", json.dumps(event))
    logger.info("ENDPOINT_URL: %s", os.environ.get("AWS_ENDPOINT_URL"))

    # test Docker SDK import
    try:
        import docker    # noqa: F401
        logger.info("Docker SDK import succeeded")
    except Exception as e:
        logger.error("Docker SDK import failed: %s", e, exc_info=True)
        # re-raise if you want the Lambda to fail here:
        raise

    for record in event.get("Records", []):
        try:
            body = json.loads(record["body"])
            job_id   = body["jobId"]
            url      = body["url"]
            filename = body["filename"]
            s3_key   = body["s3Key"]
            logger.info(
                "Processing job %s: url=%s, filename=%s, s3Key=%s",
                job_id, url, filename, s3_key
            )
        except (KeyError, json.JSONDecodeError) as e:
            logger.error("Malformed SQS record: %s", e, exc_info=True)
            continue

        # Write initial status to DynamoDB
        now = int(time.time())
        table.put_item(Item={
            "jobId":     job_id,
            "url":       url,
            "filename":  filename,
            "s3Key":     s3_key,
            "status":    "STARTED",
            "createdAt": now,
            "startedAt": now,
            "ttl":       now + ttl_days * 86400,
        })

        try:
            endpoint = os.environ.get("AWS_ENDPOINT_URL")
            if endpoint:
                # local Docker path - use Docker over HTTP instead of Unix socket
                import docker
                logger.info("Starting Docker client with HTTP connection")
                
                # Always try Docker gateway IP first, which is more reliable in container environments
                gateway_ip = "172.17.0.1"
                docker_host = os.environ.get("DOCKER_HOST", f"tcp://{gateway_ip}:2375")
                
                try:
                    logger.info(f"Connecting to Docker via gateway IP: {gateway_ip}")
                    client = docker.DockerClient(base_url=f"tcp://{gateway_ip}:2375")
                    client.ping()  # Test connection
                except Exception as e:
                    logger.warning(f"Could not connect to Docker via gateway IP: {e}")
                    # Try the configured DOCKER_HOST as fallback
                    logger.info(f"Trying to connect to Docker via DOCKER_HOST: {docker_host}")
                    client = docker.DockerClient(base_url=docker_host)
                
                logger.info("Starting local container for job %s", job_id)
                # make sure /downloads exists on the host (or bind a tmpdir of your choice)
                LOCAL_DOWNLOADS_DIR="/tmp/downloads"
                os.makedirs(LOCAL_DOWNLOADS_DIR, exist_ok=True)
                container = client.containers.run(
                    image=container_name,
                    command=[url, filename],
                    network="chronicle-network",
                    volumes={
                        # mount a downloads dir so /downloads inside the container works
                        f"{LOCAL_DOWNLOADS_DIR}": {
                            "bind": "/downloads",
                            "mode": "rw"
                        },
                        # Mount the shared volume for transmission seeding
                        "chronicle_downloads": {
                            "bind": "/var/downloads",
                            "mode": "rw"
                        },
                    },
                    environment={
                        "JOB_ID":       job_id,
                        "DDB_TABLE":    os.environ["DDB_TABLE"],
                        "S3_BUCKET":    s3_bucket,
                        "S3_KEY":       s3_key,
                        "TTL_DAYS":     str(ttl_days),
                        # Make sure we use localstack's container name inside the container network
                        "AWS_ENDPOINT_URL": "http://chronicle-localstack:4566",
                        "AWS_REGION": "us-west-1",
                        "AWS_ACCESS_KEY_ID": "test",
                        "AWS_SECRET_ACCESS_KEY": "test",
                    },
                    detach=True,
                )
                
                result = container.wait()
                exit_code = result.get("StatusCode", -1)

                logs = container.logs(stdout=True, stderr=True).decode("utf-8", errors="replace")
                logger.info("=== chronicle-recorder container logs start ===\n%s\n=== chronicle-recorder container logs end ===", logs)


                if exit_code != 0:
                    raise RuntimeError("Local container exited with code %d" % exit_code)
                    
                # Explicitly update job status to COMPLETED regardless of what the container tried to do
                logger.info("Container completed successfully, ensuring job status is COMPLETED")
                try:
                    table.update_item(
                        Key={"jobId": job_id},
                        UpdateExpression="SET #st = :s, finishedAt = :ft, torrentFile = :tf",
                        ExpressionAttributeNames={"#st": "status"},
                        ExpressionAttributeValues={
                            ":s": "COMPLETED",
                            ":ft": datetime.datetime.now().isoformat() + "Z",
                            ":tf": f"watch/{filename}.torrent"
                        },
                    )
                    logger.info("Successfully updated job status to COMPLETED in Lambda")
                except Exception as e:
                    logger.error("Failed to update job status to COMPLETED: %s", e)
                    
            else:
                # ECS / Fargate path
                ecs = boto3.client("ecs")
                logger.info("Dispatching ECS run_task for job %s", job_id)
                resp = ecs.run_task(
                    cluster=ecs_cluster,
                    launchType="FARGATE",
                    taskDefinition=ecs_task_def,
                    overrides={
                        "containerOverrides": [{
                            "name":        container_name,
                            "command":     [url, filename],
                            "environment": [
                                {"name": "S3_BUCKET", "value": s3_bucket},
                                {"name": "S3_KEY",    "value": s3_key},
                            ],
                        }]
                    },
                    networkConfiguration={
                        "awsvpcConfiguration": {
                            "subnets":        os.environ.get("SUBNET_IDS", "").split(","),
                            "securityGroups": os.environ.get("SECURITY_GROUP_IDS", "").split(","),
                            "assignPublicIp": "ENABLED",
                        }
                    },
                )
                failures = resp.get("failures", [])
                if failures:
                    raise RuntimeError("ECS run_task failures: %s" % failures)

                task_arn = resp["tasks"][0]["taskArn"]
                waiter = ecs.get_waiter("tasks_stopped")
                waiter.wait(cluster=ecs_cluster, tasks=[task_arn])
                desc = ecs.describe_tasks(cluster=ecs_cluster, tasks=[task_arn])
                exit_code = desc["tasks"][0]["containers"][0].get("exitCode", -1)
                if exit_code != 0:
                    raise RuntimeError("ECS task exited with code %d" % exit_code)

            # fetch output and upload to S3, if any
            local_path = "/tmp/%s" % filename
            if os.path.exists(local_path):
                s3.upload_file(local_path, s3_bucket, s3_key)
                os.remove(local_path)

            # mark success
            table.update_item(
                Key={"jobId": job_id},
                UpdateExpression="SET #st = :s, #ttl = :t",
                ExpressionAttributeNames={
                    "#st": "status",
                    "#ttl": "ttl"
                },
                ExpressionAttributeValues={
                    ":s": "COMPLETED",
                    ":t": datetime.datetime.now().isoformat() + "Z"
                },
            )

            logger.info("Job %s completed successfully", job_id)

        except Exception as e:
            logger.exception("Job %s failed", job_id)
            table.update_item(
                Key={"jobId": job_id},
                UpdateExpression="SET #st = :s, #err = :e",
                ExpressionAttributeNames={"#st": "status", "#err": "error"},
                ExpressionAttributeValues={
                    ":s": "FAILED",
                    ":e": str(e)
                },
            )
            # bubble up so SQS can DLQ
            raise

    return {"status": "processed"}


def handle_api_request(event, context):
    http_method = event['httpMethod']
    path = event.get('path', '')
    
    # GET /jobs - List all jobs
    if http_method == 'GET' and path == '/jobs':
        # Query DynamoDB for all jobs
        result = table.scan()
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps(result.get('Items', []))
        }
    
    # POST /jobs - Create new job
    if http_method == 'POST' and path == '/jobs':
        body = json.loads(event['body'])
        job_id = body.get('jobId')
        url = body.get('url')
        filename = body.get('filename')
        
        # Create SQS message
        sqs = boto3.client('sqs')
        sqs.send_message(
            QueueUrl=os.environ.get('SQS_QUEUE_URL'),
            MessageBody=json.dumps({
                'jobId': job_id,
                'url': url,
                'filename': filename,
                's3Key': f"recordings/{datetime.datetime.now().strftime('%Y/%m/%d')}/{filename}"
            }),
            MessageGroupId='default'
        )
        
        return {
            'statusCode': 201,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'success': True})
        }
