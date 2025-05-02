FROM alpine:3.18

# Install transmission and dependencies
RUN apk add --no-cache \
    transmission-daemon \
    transmission-cli \
    bash \
    aws-cli \
    python3 \
    py3-pip

# Create directories
RUN mkdir -p /downloads /watch /downloads/incomplete /config/transmission-home && \
    id -u transmission &>/dev/null || adduser -D -h /var/lib/transmission transmission && \
    chown -R transmission:transmission /downloads /watch /var/lib/transmission /config

# Install python dependencies
RUN pip3 install --no-cache-dir boto3

# Set up entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Transmission RPC/UI ports
EXPOSE 9091 51413/tcp 51413/udp

VOLUME ["/downloads", "/watch", "/config"]

USER transmission
WORKDIR /var/lib/transmission

ENTRYPOINT ["/entrypoint.sh"] 