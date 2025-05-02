# Web Docker Container

This directory contains the configuration for the Chronicle web frontend Docker container.

## Features

- Multi-stage build with development and production targets
- Hot reloading for local development
- Production-optimized build for deployment
- LocalStack integration for connecting to the backend services

## Usage

### Development Mode

```bash
# Start the development server with hot reloading
./util/build_web_docker.sh dev run

# Start with LocalStack integration (automatically starts LocalStack if needed)
./util/build_web_docker.sh dev run-localstack
```

### Development with Mock Data

If you're having issues connecting to LocalStack or just want to develop the frontend without backend dependencies:

```bash
# Start the development server with mock data
./util/build_web_docker.sh dev-mock
```

This mode uses in-memory mock data and doesn't require LocalStack or any other backend services.

### Production Mode

```bash
# Build and run the production container locally
./util/build_web_docker.sh prod run

# Build the production image for deployment
./util/build_web_docker.sh prod push
```

### Cleanup

```bash
# Remove all containers and volumes
./util/build_web_docker.sh clean
```

## Environment Variables

The following environment variables can be set to configure the application:

- `NEXT_PUBLIC_API_URL`: The URL of the backend API (default: `http://localstack:4566/restapis/api/prod/_user_request_`)
  - Set to `mock` to use in-memory mock data
- `NEXT_PUBLIC_POLL_INTERVAL`: Milliseconds between job status poll requests (default: 5000)

## LocalStack Integration

The web container connects directly to the LocalStack container to access:

- DynamoDB: Stores job tracking information
- SQS: Queue for job processing
- S3: Storage for recordings

This integration is configured through:

1. Shared Docker network (`chronicle-network`)
2. Direct container name resolution (`http://localstack:4566`)
3. Next.js API routes that use the AWS SDK directly (`/api/localstack-jobs.js`)

## Troubleshooting

If the web app is not connecting to LocalStack:

1. Make sure LocalStack is running: `docker ps | grep localstack`
2. Verify network connection: `docker network inspect chronicle-network`
3. Check container logs: `docker-compose logs -f web-dev`
4. View the API logs in the Next.js console

## Architecture

```
┌───────────────┐     ┌───────────────┐
│ Web Container │     │   LocalStack  │
│  (Next.js)    │─────┤   Container   │
│ Port: 3000    │     │  Port: 4566   │
└───────────────┘     └───────────────┘
        │                     │
        ▼                     ▼
  User Interface       AWS Services Simulation
                       (DynamoDB, SQS, S3, etc.)
```

## Container Structure

- **Base**: Node 18 Alpine
- **Development**: Includes hot reloading and volume mounting
- **Production**: Optimized build with standalone Next.js output

The Dockerfile uses multi-stage builds to minimize image size while maintaining development flexibility. 