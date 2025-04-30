# Delete and wipe
docker compose -f docker/localstack/docker-compose.yml down && docker volume rm localstack_localstack_data && rm terraform/backend/lambda/dispatch_to_ecs.zip

# Restore and set up
docker compose -f docker/localstack/docker-compose.yml down && docker compose -f docker/localstack/docker-compose.yml up -d  ; sleep 1 && ./docker/localstack/localstack_setup.sh

# Queue SQS
aws --endpoint-url=http://localhost:4566 sqs send-message --queue-url http://localhost:4566/000000000000/yt-jobs.fifo --message-body '{"jobId":"123","url":"https://www.youtube.com/watch?v=HEgrMoaWDIM","filename":"abc123.mkv","s3Key":"recordings/2025/04/30/abc123.mkv"}' --message-group-id default

# View logs
#docker-compose -f docker/localstack/docker-compose.yml logs -f localstack
