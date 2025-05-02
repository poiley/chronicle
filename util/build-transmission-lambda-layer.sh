#!/bin/bash
set -euo pipefail

# Create directories
LAYER_DIR="$(mktemp -d)"
mkdir -p "$LAYER_DIR/bin"
mkdir -p "$LAYER_DIR/lib"

echo "Building Lambda layer for transmission-cli in $LAYER_DIR"

# We'll use a Docker container based on Amazon Linux 2 to build the layer
# This ensures compatibility with the Lambda runtime environment
cat > Dockerfile.lambda-layer << EOF
FROM amazonlinux:2

# Install transmission-cli and its dependencies
RUN yum update -y && \
    yum install -y yum-utils && \
    yum-config-manager --enable epel && \
    yum install -y epel-release && \
    yum install -y transmission-cli

# Create layer structure
RUN mkdir -p /opt/bin /opt/lib

# Copy binaries
RUN cp /usr/bin/transmission-create /opt/bin/ && \
    chmod 755 /opt/bin/transmission-create

# Copy required libraries
RUN for lib in \$(ldd /usr/bin/transmission-create | grep -oP '=> \K/lib.*|/usr/lib.*' | cut -d' ' -f1); do \
      cp \$lib /opt/lib/; \
    done

# Make libraries executable
RUN chmod 755 /opt/lib/*
EOF

# Build the Docker image
echo "Building Docker image for layer creation"
docker build -t transmission-lambda-layer -f Dockerfile.lambda-layer .

# Run the container and extract the layer files
echo "Extracting layer files from container"
docker run --rm -v "$LAYER_DIR:/output" transmission-lambda-layer \
  bash -c "cp -r /opt/* /output/"

# Create the layer zip file
echo "Creating layer zip file"
OUTPUT_DIR="terraform/backend/lambda"
mkdir -p "$OUTPUT_DIR"
cd "$LAYER_DIR"
zip -r "$OLDPWD/$OUTPUT_DIR/transmission_tools_layer.zip" .
cd - > /dev/null

echo "Lambda layer created at $OUTPUT_DIR/transmission_tools_layer.zip"
echo "Layer size: $(du -h $OUTPUT_DIR/transmission_tools_layer.zip | cut -f1)"

# Cleanup
rm -f Dockerfile.lambda-layer
rm -rf "$LAYER_DIR"

echo "Layer creation complete!" 