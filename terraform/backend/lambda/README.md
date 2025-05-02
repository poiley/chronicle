# LocalStack Quickstart Guide

A minimal guide to run AWS services locally with LocalStack via Docker Compose.

---

## 1. Prerequisites

- Docker & Docker Compose installed  
- (Optional) Python 3 & `pip` for `awscli-local` wrapper  
- (Optional) AWS CLI v2

---

## 2. Docker Compose Configuration

Create a file named `docker-compose.yml`:

```yaml
version: '3.8'
services:
  localstack:
    image: localstack/localstack:latest
    ports:
      - "4566:4566"       # Main edge port (all services)
      - "4571:4571"       # Optional legacy port
    environment:
      - SERVICES=s3,sqs,dynamodb,lambda,apigateway
      - DEBUG=1
      - DATA_DIR=/data
      - AWS_ACCESS_KEY_ID=test
      - AWS_SECRET_ACCESS_KEY=test
      - AWS_DEFAULT_REGION=us-east-1
      - LAMBDA_EXECUTOR=docker
    volumes:
      - localstack_data:/data
      - /var/run/docker.sock:/var/run/docker.sock
    restart: always

volumes:
  localstack_data:
```

---

## 3. Start LocalStack

```bash
docker-compose up -d
```

- Check logs:  
  ```bash
  docker-compose logs -f localstack
  ```

---

## 4. Health Check

LocalStack’s public health endpoint has moved under an internal path:

```bash
curl http://localhost:4566/_localstack/health
# or filter by service
curl http://localhost:4566/_localstack/health?services=s3,sqs,lambda
```

---

## 5. AWS CLI Usage

### 5.1 Environment

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1
```

### 5.2 Direct Calls

Use the `--endpoint-url` flag:

```bash
aws --endpoint-url=http://localhost:4566 s3 ls
aws --endpoint-url=http://localhost:4566 sqs list-queues
aws --endpoint-url=http://localhost:4566 dynamodb list-tables
aws --endpoint-url=http://localhost:4566 lambda list-functions
```

### 5.3 `awscli-local` (Optional)

```bash
pip install awscli-local
awslocal s3 mb s3://my-bucket
awslocal sqs create-queue --queue-name my-queue
```

---

## 6. SDK Usage (Python / Boto3)

```python
import boto3

client = boto3.client(
    's3',
    endpoint_url='http://localhost:4566',
    aws_access_key_id='test',
    aws_secret_access_key='test',
    region_name='us-east-1'
)

# Example: list buckets
print(client.list_buckets())
```

---

## 7. Tips & Troubleshooting

- **Lambda in Docker**: ensure `/var/run/docker.sock` is mounted and `LAMBDA_EXECUTOR=docker`.  
- **Port Conflicts**: only one process may bind port 4566.  
- **Persisting Data**: LocalStack stores state under `/data` (mapped to `localstack_data`).  
- **Logs & Debugging**: set `DEBUG=1` for verbose output.  

---
