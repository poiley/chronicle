import os
import json
import requests
import boto3
from datetime import datetime
from botocore.exceptions import ClientError

ecs   = boto3.client('ecs')
ddb   = boto3.resource('dynamodb')
table = ddb.Table(os.environ['DDB_TABLE'])

def now_iso():
    return datetime.utcnow().isoformat() + 'Z'

def lambda_handler(event, context):
    cluster      = os.environ['ECS_CLUSTER']
    task_def     = os.environ['ECS_TASK_DEF']
    s3_bucket    = os.environ['S3_BUCKET']
    container    = os.environ['CONTAINER_NAME']

    for record in event['Records']:
        body    = json.loads(record['body'])
        job_id  = body['jobId']
        url     = body['url']
        fn      = body['filename']
        s3_key  = body.get('s3Key', f"recordings/{fn}")

        # 1) PENDING → write initial job row
        table.put_item(Item={
            'jobId':       job_id,
            'url':         url,
            'filename':    fn,
            's3Key':       s3_key,
            'status':      'PENDING',
            'createdAt':   now_iso()
        })

        # 2) Validate video exists
        resp = requests.get(
            "https://www.youtube.com/oembed",
            params={"url": url},
            timeout=5
        )
        if resp.status_code != 200:
            raise Exception(f"Video not found: {url}")

        # 3) STARTED → after ECS run_task
        try:
            resp = ecs.run_task(
                cluster=cluster,
                launchType='FARGATE',
                taskDefinition=task_def,
                overrides={
                    'containerOverrides': [{
                        'name':    container,
                        'command': [url, fn],
                        'environment': [
                            {'name':'S3_BUCKET','value':s3_bucket},
                            {'name':'S3_KEY',   'value':s3_key},
                            {'name':'JOB_ID',   'value':job_id},
                            {'name':'DDB_TABLE','value':os.environ['DDB_TABLE']},
                            {'name':'TTL_DAYS','value':os.environ.get('TTL_DAYS','30')}
                        ]
                    }]
                },
                networkConfiguration={
                    'awsvpcConfiguration': {
                        'subnets':        os.environ['SUBNET_IDS'].split(','),
                        'securityGroups': os.environ['SECURITY_GROUP_IDS'].split(','),
                        'assignPublicIp': 'ENABLED'
                    }
                }
            )
        except ClientError as e:
            raise

        table.update_item(
            Key={'jobId': job_id},
            UpdateExpression='SET #s = :s, startedAt = :st',
            ExpressionAttributeNames={'#s':'status'},
            ExpressionAttributeValues={
                ':s':  'STARTED',
                ':st': now_iso()
            }
        )

    return {'statusCode':200,'body':'Dispatched'}
