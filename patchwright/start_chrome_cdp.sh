#!/bin/bash
# Chrome CDP startup script for supervisor
set -e

# Enable debugging
echo "=== Chrome CDP Startup Debug Info ==="
echo "CDP_STANDALONE_PORT: ${CDP_STANDALONE_PORT:-9221}"
echo "DISPLAY: ${DISPLAY:-:99}"
echo "USER: $(whoami)"
echo "HOSTNAME: $(hostname)"
echo "PWD: $(pwd)"
echo "Date: $(date)"

# Find Chrome binary - prioritize regular chrome over headless_shell
CHROME_PATH=$(find /ms-playwright -path "*/chrome-linux/chrome" -type f | head -1)

if [ -z "$CHROME_PATH" ]; then
    echo "ERROR: Chrome binary not found in /ms-playwright"
    find /ms-playwright -name "*chrome*" -type f || echo "No chrome-related files found"
    exit 1
fi

echo "Chrome binary found: $CHROME_PATH"

# Check if Chrome binary is executable
if [ ! -x "$CHROME_PATH" ]; then
    echo "ERROR: Chrome binary is not executable"
    ls -la "$CHROME_PATH"
    exit 1
fi

echo "Starting Chrome CDP server on port ${CDP_STANDALONE_PORT:-9221}"

# Set display
export DISPLAY=:99

# Wait for X server to be ready with proper timeout
echo "Waiting for X server..."
X_READY=false
for attempt in {1..60}; do
    if xset q &>/dev/null; then
        echo "X server is ready"
        X_READY=true
        break
    fi
    echo "Waiting for X server to start... (attempt $attempt/60)"
    sleep 1
done

# Check if X server is ready, if not, try some diagnostics
if [ "$X_READY" = false ]; then
    echo "WARNING: X server not detected after 60 seconds"
    echo "X server diagnostics:"
    ps aux | grep Xvfb || echo "No Xvfb process found"
    ls -la /tmp/.X11-unix/ || echo "No X11 sockets found"
    echo "DISPLAY=${DISPLAY}"
    
    # Continue anyway - Chrome might still work or fail gracefully
    echo "Continuing anyway..."
fi

# Clean up any existing Chrome processes
pkill -f "chrome.*--remote-debugging-port" || true
sleep 2

# Create user data directory with proper permissions
mkdir -p /tmp/chrome-cdp-profile
chmod 755 /tmp/chrome-cdp-profile

# Clean and reset profile directory to ensure proper ownership
if [ "$(whoami)" = "patchright" ]; then
    # If running as patchright user, clean up any root-owned files
    sudo rm -rf /tmp/chrome-cdp-profile/* 2>/dev/null || true
    mkdir -p /tmp/chrome-cdp-profile
    chmod 755 /tmp/chrome-cdp-profile
fi

# Start Chrome with CDP in background
"$CHROME_PATH" \
  --disable-dbus \
  --disable-dev-shm-usage \
  --disable-background-timer-throttling \
  --disable-backgrounding-occluded-windows \
  --disable-renderer-backgrounding \
  --remote-debugging-port=${CDP_STANDALONE_PORT:-9221} \
  --remote-debugging-address=0.0.0.0 \
  --disable-gpu \
  --window-size=1920,1080 \
  --user-data-dir=/tmp/chrome-cdp-profile \
  --use-gl=swiftshader \
  --no-first-run \
  --no-default-browser-check \
  --disable-infobars \
  --disable-notifications \
  --disable-translate \
  --disable-features=VizDisplayCompositor,TranslateUI \
  --disable-extensions \
  --disable-logging \
  --disable-default-apps \
  --disable-hang-monitor \
  --disable-prompt-on-repost \
  --disable-sync \
  --disable-background-networking \
  --metrics-recording-only \
  --disable-component-extensions-with-background-pages &
# Store Chrome PID
CHROME_PID=$!
echo "Chrome started with PID: $CHROME_PID"

# Wait a moment for Chrome to start
sleep 5

# Verify Chrome is running and CDP is accessible
echo "Verifying CDP server..."
for i in {1..15}; do
    if curl -s "http://127.0.0.1:${CDP_STANDALONE_PORT:-9221}/json" > /dev/null 2>&1; then
        echo "✅ CDP server is accessible on port ${CDP_STANDALONE_PORT:-9221}"
        echo "Chrome CDP endpoints:"
        curl -s "http://127.0.0.1:${CDP_STANDALONE_PORT:-9221}/json" | head -3
        break
    else
        echo "⏳ Waiting for CDP server... (attempt $i/15)"
        sleep 2
    fi
    
    if [ $i -eq 15 ]; then
        echo "❌ CDP server failed to start properly"
        echo "Chrome process status:"
        ps aux | grep chrome || echo "No chrome processes found"
        echo "Port status:"
        netstat -ln | grep ":${CDP_STANDALONE_PORT:-9221}" || echo "Port ${CDP_STANDALONE_PORT:-9221} not listening"
        echo "Chrome logs:"
        ls -la /tmp/chrome-cdp-profile/ || echo "No chrome profile directory"
        exit 1
    fi
done

# Create a monitoring loop that restarts Chrome if it dies
echo "Chrome CDP server is running. Starting monitoring loop..."
while true; do
    if ! kill -0 $CHROME_PID 2>/dev/null; then
        echo "⚠️ Chrome process died, restarting..."
        # Clean up
        pkill -f "chrome.*--remote-debugging-port" || true
        sleep 2
        
        # Restart Chrome
        "$CHROME_PATH" \
          --disable-dbus \
          --disable-dev-shm-usage \
          --disable-background-timer-throttling \
          --disable-backgrounding-occluded-windows \
          --disable-renderer-backgrounding \
          --remote-debugging-port=${CDP_STANDALONE_PORT:-9221} \
          --remote-debugging-address=0.0.0.0 \
          --disable-gpu \
          --window-size=1920,1080 \
          --user-data-dir=/tmp/chrome-cdp-profile \
          --use-gl=swiftshader \
          --no-first-run \
          --no-default-browser-check \
          --disable-infobars \
          --disable-notifications \
          --disable-translate \
          --disable-features=VizDisplayCompositor,TranslateUI \
          --disable-extensions \
          --disable-logging \
          --disable-default-apps \
          --disable-hang-monitor \
          --disable-prompt-on-repost \
          --disable-sync \
          --disable-background-networking \
          --metrics-recording-only \
          --disable-component-extensions-with-background-pages &
        
        CHROME_PID=$!
        echo "Chrome restarted with PID: $CHROME_PID"
        sleep 5
    fi
    
    # Check every 10 seconds
    sleep 10
done
