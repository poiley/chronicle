# Use a slim Python base with bash
FROM python:3.11-slim

# Set AWS configuration environment variables
ENV AWS_REGION="us-west-1"
ENV AWS_DEFAULT_REGION="us-west-1"

# Install ffmpeg, curl, unzip
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ffmpeg curl unzip \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
RUN unzip awscliv2.zip
RUN ./aws/install

# Install yt-dlp
RUN pip install --no-cache-dir yt-dlp

# Create app directory
WORKDIR /app

# Copy entrypoint (which now includes stream download logic)
COPY entrypoint.sh /app/entrypoint.sh

# Make entrypoint executable
RUN chmod +x /app/entrypoint.sh

# Mount point for recordings
VOLUME ["/downloads"]

# Use entrypoint.sh directly
ENTRYPOINT ["/app/entrypoint.sh"]
