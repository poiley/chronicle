# Use a slim Python base with bash
FROM python:3.11-slim

# Install ffmpeg (for segment merge) and curl
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ffmpeg curl \
    && rm -rf /var/lib/apt/lists/*

# Install yt-dlp
RUN pip install --no-cache-dir yt-dlp

# Create app directory
WORKDIR /app

# Copy entrypoint (which now includes stream download logic)
COPY docker/ecs/entrypoint.sh /app/entrypoint.sh

# Make entrypoint executable
RUN chmod +x /app/entrypoint.sh

# Mount point for recordings
VOLUME ["/downloads"]

# Use entrypoint.sh directly
ENTRYPOINT ["/app/entrypoint.sh"]
