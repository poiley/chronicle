FROM localstack/localstack:latest

USER root
RUN apt-get update && apt-get install -y docker.io curl vim && rm -rf /var/lib/apt/lists/*

ENV SERVICES="s3,sqs,dynamodb,lambda,apigateway"
ENV DEBUG=1
ENV AWS_ACCESS_KEY_ID=test
ENV AWS_SECRET_ACCESS_KEY=test
ENV AWS_DEFAULT_REGION=us-west-1
ENV LAMBDA_EXECUTOR=docker

# Copy custom AWS init scripts
COPY torrent_lambda_setup.sh /docker-entrypoint-initaws.d/
COPY localstack_setup.sh /docker-entrypoint-initaws.d/