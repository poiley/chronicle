# Utility Scripts

This directory contains essential scripts for managing the Chronicle development environment and infrastructure.

## Core Scripts

### `setup.sh`
The main setup script for initializing the development environment. It:
- Sets up Docker networking
- Starts LocalStack with required services
- Builds and starts all necessary containers (web, recorder, transmission, opentracker)
- Configures CORS and tracker settings
- Provides a complete local development environment

```bash
./setup.sh
```

### `check_and_fix_job_status.sh`
Helps manage job statuses in LocalStack's DynamoDB, which can sometimes be inconsistent due to eventual consistency. The script:
- Checks for jobs stuck in intermediate states
- Verifies actual file existence in S3
- Updates job statuses based on actual state
- Cleans up orphaned or failed jobs

```bash
./check_and_fix_job_status.sh
```

### `test_e2e_flow.sh`
Tests the complete end-to-end workflow by:
- Submitting a test recording job
- Monitoring its progress through all stages
- Verifying S3 uploads and torrent creation
- Checking DynamoDB status updates

```bash
./test_e2e_flow.sh <youtube_url> <output_filename>
```

## Configuration Scripts

### `track-ip-config.sh`
Configures the opentracker's IP address across all relevant configuration files. Run this after the opentracker container is up to ensure all components use the correct tracker URL.

```bash
./track-ip-config.sh
```

### `fix_localstack_cors.sh`
Sets up CORS configuration for LocalStack's API Gateway to allow web UI interactions. This is automatically called by `setup.sh` but can be run independently if needed.

```bash
./fix_localstack_cors.sh
```

### `update_lambda_docker_host.sh`
Updates Lambda functions to use the correct Docker host when running in LocalStack. This ensures proper container spawning in the development environment.

```bash
./update_lambda_docker_host.sh
```

## Build Scripts

### `build_web_docker.sh`
Builds and manages the web UI Docker container. Supports both development and production modes.

```bash
# Development mode with hot reloading
./build_web_docker.sh dev

# Production build
./build_web_docker.sh prod
```

## Script Dependencies

The scripts have the following dependencies:
- Docker and Docker Compose
- AWS CLI (configured for LocalStack)
- curl
- jq (for JSON processing)
- sed and standard Unix tools

## Environment Variables

The scripts respect the following environment variables:
- `AWS_ENDPOINT_URL`: Set to `http://localhost:4566` for LocalStack
- `AWS_DEFAULT_REGION`: Defaults to `us-west-1`
- `AWS_ACCESS_KEY_ID`: Set to `test` for LocalStack
- `AWS_SECRET_ACCESS_KEY`: Set to `test` for LocalStack 