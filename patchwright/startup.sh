#!/bin/bash
set -e

echo "Starting Patchright CDP + noVNC container..."

# Ensure display is available
export DISPLAY=:99

# Create necessary directories with proper permissions
mkdir -p /tmp/chrome-profile /tmp/supervisor /var/log/supervisor
chmod 755 /tmp/chrome-profile /tmp/supervisor /var/log/supervisor

# Set proper ownership
chown patchright:patchright /tmp/chrome-profile /tmp/supervisor /var/log/supervisor

# Ensure environment variables are set
export VNC_PORT=${VNC_PORT:-5901}
export NOVNC_PORT=${NOVNC_PORT:-6080}
export CDP_PORT=${CDP_PORT:-9222}
export API_PORT=${API_PORT:-8000}
export CDP_API_PORT=${CDP_API_PORT:-8080}

echo "Environment variables set:"
echo "VNC_PORT=$VNC_PORT"
echo "NOVNC_PORT=$NOVNC_PORT" 
echo "CDP_PORT=$CDP_PORT"
echo "API_PORT=$API_PORT"
echo "CDP_API_PORT=$CDP_API_PORT"

# Execute the CMD (should be supervisord)
echo "Starting supervisord..."
exec "$@"
