#!/bin/bash
set -e

echo "Starting Patchright CDP + noVNC co# Check if proxy started successfully
if ps aux | grep -v grep | grep cdp_proxy_simple.js > /dev/null; then
    echo "✅ CDP Proxy started successfully"
else
    echo "❌ CDP Proxy failed to start, check /tmp/cdp_proxy.log"er..."

# Ensure display is available
export DISPLAY=:99

# Create necessary directories with proper permissions
mkdir -p /tmp/chrome-profile /tmp/supervisor /var/log/supervisor
chmod 755 /tmp/chrome-profile /tmp/supervisor /var/log/supervisor

# Set proper ownership

# Handle ownership of large directories at runtime to avoid Docker build memory issues
echo "Setting ownership for Playwright and Python venv directories..."
chown -R patchright:patchright /ms-playwright /opt/venv || echo "Warning: Could not set ownership for some directories"
chown patchright:patchright /tmp/chrome-profile /tmp/supervisor /var/log/supervisor

# Ensure CDP proxy script has proper permissions
chown patchright:patchright /usr/local/bin/cdp_proxy_simple.js
chmod +x /usr/local/bin/cdp_proxy_simple.js

chown patchright:patchright /usr/local/bin/start_chrome_cdp.sh
chmod +x /usr/local/bin/start_chrome_cdp.sh

# Ensure environment variables are set
export VNC_PORT=${VNC_PORT:-5901}
export NOVNC_PORT=${NOVNC_PORT:-6080}
export CDP_PORT=${CDP_PORT:-9223}
export CDP_STANDALONE_PORT=${CDP_STANDALONE_PORT:-9221}
export API_PORT=${API_PORT:-8000}
export CDP_API_PORT=${CDP_API_PORT:-8080}

# Try to detect external host for CDP proxy using hostname command
SANDBOX_ID=$(hostname)
if [ -n "$SANDBOX_ID" ]; then
    # Construct the external host using the sandbox ID from hostname
    export EXTERNAL_HOST="${CDP_PORT}-${SANDBOX_ID}.proxy.daytona.work"
    echo "Detected Daytona sandbox ID: $SANDBOX_ID"
    echo "CDP external host: $EXTERNAL_HOST"
fi

echo "Environment variables set:"
echo "VNC_PORT=$VNC_PORT"
echo "NOVNC_PORT=$NOVNC_PORT"
echo "CDP_PORT=$CDP_PORT"
echo "CDP_STANDALONE_PORT=$CDP_STANDALONE_PORT"
echo "API_PORT=$API_PORT"
echo "CDP_API_PORT=$CDP_API_PORT"
echo "EXTERNAL_HOST=${EXTERNAL_HOST:-auto-detect}"

# Add this before starting Chrome CDP
echo "Ensuring X server is available..."
if ! pgrep -x Xvfb > /dev/null; then
    echo "Starting Xvfb manually..."
    Xvfb :99 -screen 0 1920x1080x24 -ac &
    sleep 3
    echo "Xvfb started, waiting for socket..."
    for i in {1..10}; do
        if [ -e /tmp/.X11-unix/X99 ]; then
            echo "✅ X server socket found"
            break
        fi
        echo "Waiting for X server socket... ($i/10)"
        sleep 1
    done
fi

# Start Chrome CDP in background (self-managed, not by supervisord)
echo "Starting Chrome CDP in background (self-managed)..."
su - patchright -c "export CDP_STANDALONE_PORT=$CDP_STANDALONE_PORT; export DISPLAY=$DISPLAY; /usr/local/bin/start_chrome_cdp.sh" > /tmp/chrome_cdp.log 2>&1 &
# Wait a moment for Chrome to start
sleep 3

# Check if Chrome CDP started successfully
if ps aux | grep -v grep | grep "chrome.*--remote-debugging-port" > /dev/null; then
    echo "✅ Chrome CDP started successfully"
else
    echo "❌ Chrome CDP failed to start, check /tmp/chrome_cdp.log"
    cat /tmp/chrome_cdp.log 2>/dev/null || echo "No Chrome CDP log file found"
fi

# Start CDP Proxy in background (self-managed, not by supervisord)
echo "Starting CDP Proxy in background (self-managed)..."
echo "CDP Proxy log will be at /tmp/cdp_proxy.log"
su - patchright -c bash <<'EOF' &
export CDP_STANDALONE_PORT="$CDP_STANDALONE_PORT"
export CDP_PORT="$CDP_PORT"
export EXTERNAL_HOST="$EXTERNAL_HOST"
node /usr/local/bin/cdp_proxy_simple.js > /tmp/cdp_proxy.log 2>&1
EOF

# Wait a moment for proxy to start
sleep 2

# Check if proxy started successfully
if ps aux | grep -v grep | grep cdp_proxy_simple.js > /dev/null; then
    echo "✅ CDP Proxy started successfully"
else
    echo "❌ CDP Proxy failed to start, check /tmp/cdp_proxy.log"
    cat /tmp/cdp_proxy.log 2>/dev/null || echo "No log file found"
fi

# Trap signals to ensure graceful shutdown
trap 'echo "Received termination signal, shutting down..."; supervisorctl -c /etc/supervisor/conf.d/supervisord.conf shutdown; exit 0' TERM INT

# Start supervisord in foreground to manage other services (keeps container alive)
echo "Starting supervisord in foreground to manage other services..."
echo "Container will run indefinitely with supervisord managing services and Chrome running independently..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf