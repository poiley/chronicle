# S3 Torrent Creator

This project allows you to automatically create torrents from files uploaded to S3 and seed them using the Transmission client and a custom BitTorrent tracker.

## Overview

The system consists of the following components:

1. **LocalStack** - Provides a local S3-compatible API for testing
2. **BitTorrent Tracker** - Based on OpenTracker, provides tracker services
3. **Transmission** - BitTorrent client for seeding torrents
4. **S3 Torrent Creator** - Python service that monitors S3 for new files, creates torrents, and seeds them

## Architecture

```
                     ┌───────────────┐
                     │     S3        │
                     │  (LocalStack) │
                     └───────┬───────┘
                             │
                             ▼
┌───────────────┐    ┌───────────────┐    ┌───────────────┐
│   BitTorrent  │◄───┤  S3 Torrent   │───►│  Transmission │
│    Tracker    │    │    Creator    │    │    Client     │
└───────────────┘    └───────────────┘    └───────────────┘
```

## How It Works

1. Files are uploaded to S3
2. The S3 Torrent Creator monitors the S3 bucket for new files
3. When a new file is detected:
   - It's downloaded to the local filesystem
   - A torrent file is created using `transmission-create`
   - The torrent file is uploaded back to S3
   - The torrent is added to Transmission for seeding
4. Clients can download the torrent file from S3 and connect to the seeder

## Setup & Usage

### Quick Start

Use the provided demo script to test the system:

```bash
./s3-torrent-demo.sh
```

This script will:
1. Create necessary directories
2. Start LocalStack, the Tracker, and Transmission
3. Create a test bucket and upload a sample file
4. Start the S3 Torrent Creator to process the file
5. Verify the torrent was created

### Manual Setup

```bash
# Start all services
docker-compose -f docker-compose-simple.yml up -d

# Upload a file to S3
aws --endpoint-url=http://localhost:4566 s3 cp myfile.mp4 s3://chronicle-recordings-dev/

# The S3 Torrent Creator will automatically:
# 1. Download the file
# 2. Create a torrent
# 3. Upload the torrent to S3
# 4. Add the torrent to Transmission for seeding

# Check the status in the Transmission web UI
open http://localhost:9091
```

## Configuration

The S3 Torrent Creator uses a config file at `config/s3-torrent-creator.json` with the following options:

```json
{
  "bucket_name": "chronicle-recordings-dev",
  "prefix": "",                            // Optional S3 key prefix to monitor
  "region": "us-east-1",
  "endpoint_url": "http://localstack:4566", // For LocalStack or other S3-compatible services
  "download_dir": "/downloads",            // Where to store downloaded files
  "watch_dir": "/watch",                   // Where to place torrent files (monitored by Transmission)
  "tracker_host": "tracker",              // BitTorrent tracker hostname
  "tracker_port": 6969,                   // BitTorrent tracker port
  "poll_interval": 60,                    // How often to check S3 (in seconds)
  "aws_access_key_id": "test",            // For LocalStack
  "aws_secret_access_key": "test"         // For LocalStack
}
```

For production use, remove the `endpoint_url`, `aws_access_key_id`, and `aws_secret_access_key` options and configure proper AWS credentials.

## Deploying to Production

For production deployment:

1. Update the config file with production S3 bucket and AWS region
2. Remove LocalStack-specific settings
3. Use a publicly accessible tracker or set up your own
4. Deploy using Docker Compose or Kubernetes

## Troubleshooting

- Check logs: `docker logs s3-torrent-creator`
- Verify Transmission is running: Open http://localhost:9091
- Test S3 access: `aws --endpoint-url=http://localhost:4566 s3 ls s3://chronicle-recordings-dev/` 