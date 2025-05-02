FROM alpine:latest as builder

# Install build dependencies
RUN apk add --no-cache \
    gcc \
    g++ \
    make \
    git \
    cvs \
    zlib-dev \
    curl \
    iproute2

# Build libowfat
RUN cvs -d :pserver:cvs@cvs.fefe.de:/cvs -z9 co libowfat \
    && cd libowfat \
    && make

# Build opentracker
RUN git clone git://erdgeist.org/opentracker \
    && cd opentracker \
    && make

# Runtime stage
FROM alpine:latest

# Install runtime dependencies
RUN apk add --no-cache \
    curl \
    iproute2

# Copy built binaries and scripts
COPY --from=builder /opentracker/opentracker /usr/local/bin/
COPY --from=builder /libowfat/libowfat.a /usr/local/lib/
COPY detect-ip.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/detect-ip.sh

# Create entrypoint script
RUN echo '#!/bin/sh\n\
echo "Detecting public IP..."\n\
IP=$(/usr/local/bin/detect-ip.sh)\n\
echo "Detected public IP: $IP"\n\
echo "Starting tracker on $IP:6969"\n\
exec /usr/local/bin/opentracker -i "$IP" -p 6969 -P 6969' > /entrypoint.sh \
    && chmod +x /entrypoint.sh

EXPOSE 6969
EXPOSE 6969/udp

ENTRYPOINT ["/entrypoint.sh"] 