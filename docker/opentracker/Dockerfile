FROM ubuntu:24.04 as builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    cvs \
    git \
    zlib1g-dev \
    curl \
    iproute2 \
    gcc-multilib \
    g++-multilib \
    && rm -rf /var/lib/apt/lists/*

# Build libowfat
RUN cvs -d :pserver:cvs@cvs.fefe.de:/cvs -z9 co libowfat \
    && cd libowfat && make

# Build opentracker
RUN git clone https://erdgeist.org/gitweb/opentracker.git \
    && cd opentracker \
    && make

# Runtime stage
FROM ubuntu:24.04

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    curl \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

# Copy built binaries and scripts
COPY --from=builder /opentracker/opentracker /usr/local/bin/
COPY --from=builder /libowfat/libowfat.a /usr/local/lib/
COPY docker/opentracker/detect-ip.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/detect-ip.sh

# Create entrypoint script
RUN echo '#!/bin/bash\n\
echo "Detecting public IP..."\n\
IP=$(/usr/local/bin/detect-ip.sh)\n\
echo "Detected public IP: $IP"\n\
echo "Starting tracker on $IP:6969"\n\
exec /usr/local/bin/opentracker -i "$IP" -p 6969 -P 6969' > /entrypoint.sh \
    && chmod +x /entrypoint.sh

# Run as root for proper port binding
USER root

ENTRYPOINT ["/entrypoint.sh"] 