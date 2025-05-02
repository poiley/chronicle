# Tracker IP Configuration Setup

This document describes how the system is configured to use the opentracker instance's actual public IP address instead of a hardcoded domain name.

## Background

The torrent system requires a BitTorrent tracker for proper operation. Previously, the system was using a hardcoded domain (`opentracker.example.com`) which wasn't correct. Instead, we need to use the actual public IP address of the opentracker instance.

## Solution

We implemented a dynamic IP detection and configuration mechanism:

1. The opentracker container detects its public IP on startup using multiple methods
2. The IP is stored in `/tmp/public-ip` inside the container
3. New configuration scripts read this IP and update all relevant configuration files

## Components Modified

- Created `util/track-ip-config.sh` - Main script to detect and configure tracker IP
- Updated `docker/localstack/s3-torrent-lambda-setup.sh` - Added dynamic IP detection
- Updated `util/rebuild_images_no_cache.sh` - Added tracker IP configuration step
- Updated `util/start_development.sh` - Added tracker IP configuration step
- Updated documentation in `terraform/backend/lambda/README-s3-torrent.md`

## How It Works

1. **IP Detection**: The system uses multiple methods to detect the public IP:
   - First tries to read from tracker container's `/tmp/public-ip` file
   - Falls back to querying public IP services (api.ipify.org, ifconfig.me, icanhazip.com)
   - As a last resort, uses the local network IP

2. **Configuration Propagation**: The detected IP is used to update:
   - `tracker-config.json` - The central tracker configuration
   - Lambda environment variables in LocalStack
   - Default values in Lambda functions' Python code
   - Terraform configuration for production deployment
   - ECS entrypoint.sh script used for direct uploads

## Usage

### During Development

Simply run:
```bash
./util/track-ip-config.sh
```

This command will automatically detect the tracker IP and update all configuration files.

### During Deployment

The `rebuild_images_no_cache.sh` script now automatically runs the IP configuration, so no manual steps are needed.

## Manual Configuration

If needed, you can manually set the tracker IP:

1. Edit `terraform/backend/lambda/tracker-config.json`
2. Update the `TRACKERS` environment variable in Terraform and Lambda setup scripts
3. Modify the tracker URL in `docker/ecs/entrypoint.sh`

## Testing

To verify the configuration:

1. Start the opentracker container
2. Run `./util/track-ip-config.sh`
3. Check the output to confirm the detected IP
4. Verify the configuration files have been updated with the correct IP
5. Upload a file and confirm the torrent file is created with the correct tracker