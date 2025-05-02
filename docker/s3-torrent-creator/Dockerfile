FROM alpine:3.18

# Install dependencies
RUN apk add --no-cache \
    python3 \
    py3-pip \
    transmission-cli \
    bash \
    aws-cli \
    curl

# Install Python dependencies
RUN pip3 install --no-cache-dir \
    boto3 \
    botocore

# Create required directories
RUN mkdir -p /app /downloads /watch /config

# Copy scripts and config
COPY util/s3-torrent-creator.py /app/
RUN chmod +x /app/s3-torrent-creator.py

# Set default config path
ENV CONFIG_PATH="/config/s3-torrent-creator.json"

# Default command
CMD ["python3", "/app/s3-torrent-creator.py", "--config", "/config/s3-torrent-creator.json"] 