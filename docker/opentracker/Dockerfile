FROM alpine:latest as builder

# Install build dependencies without version pinning
RUN apk add --no-cache \
    gcc \
    g++ \
    make \
    git \
    cvs \
    zlib-dev \
    curl

# Set working directory
WORKDIR /build

# Build libowfat
RUN cvs -d :pserver:cvs@cvs.fefe.de:/cvs -z9 co libowfat && \
    cd libowfat && \
    make -j$(nproc)

# Build opentracker with IPv4 only and debug enabled
RUN git clone git://erdgeist.org/opentracker && \
    cd opentracker && \
    make -j$(nproc) FEATURES+=-DWANT_V4_ONLY FEATURES+=-DWANT_FULLSCRAPE FEATURES+=-D_DEBUG_HTTPERROR

# Simple runtime stage - minimal image
FROM alpine:latest

# Install runtime dependencies including diagnostic tools
RUN apk add --no-cache \
    curl \
    iproute2 \
    tzdata \
    bash \
    coreutils \
    net-tools \
    procps \
    strace \
    tcpdump

# Set timezone to UTC for consistent logging
ENV TZ=UTC

# Copy the binary from the builder
COPY --from=builder /build/opentracker/opentracker /usr/local/bin/
COPY detect-ip.sh /usr/local/bin/detect-ip
COPY entrypoint.sh /entrypoint.sh

# Set permissions
RUN chmod +x /usr/local/bin/detect-ip /entrypoint.sh

# Create a directory for logs
RUN mkdir -p /var/log/opentracker

# Expose TCP and UDP ports
EXPOSE 6969/tcp
EXPOSE 6969/udp

# Define entrypoint
ENTRYPOINT ["/entrypoint.sh"] 