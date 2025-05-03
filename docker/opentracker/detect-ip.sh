#!/bin/sh

# Try multiple methods to get the public IP
get_ip() {
    # Method 1: Use ipify.org
    ip=$(curl -s https://api.ipify.org)
    if [ $? -eq 0 ] && [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi

    # Method 2: Use ifconfig.me
    ip=$(curl -s https://ifconfig.me)
    if [ $? -eq 0 ] && [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi

    # Method 3: Use icanhazip.com
    ip=$(curl -s https://icanhazip.com)
    if [ $? -eq 0 ] && [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi

    # If all methods fail, use the host's IP
    # This requires the container to be run with --network=host
    ip=$(ip route get 1 | awk '{print $7}')
    if [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi

    # If everything fails, use a default
    echo "127.0.0.1"
    return 1
}

# Get the IP and store it in a file
IP=$(get_ip)
echo "$IP" > /tmp/public-ip
echo "$IP" 