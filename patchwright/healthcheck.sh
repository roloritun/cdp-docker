#!/bin/bash

# Check if supervisord is running
if ! pgrep -f "supervisord" > /dev/null; then
    echo "Supervisord is not running"
    exit 1
fi

# Check if X server is running
if ! pgrep -x "Xvfb" > /dev/null; then
    echo "X server is not running"
    exit 1
fi

# Check if VNC is running
if ! pgrep -x "x11vnc" > /dev/null; then
    echo "VNC server is not running"
    exit 1
fi

# Check if noVNC is running
if ! pgrep -f "websockify" > /dev/null; then
    echo "noVNC is not running"
    exit 1
fi

# Check if browser API is running
if ! pgrep -f "browser_api.main" > /dev/null; then
    echo "Browser API is not running"
    exit 1
fi

# Check if Chrome CDP is running and accessible via proxy
if ! curl -s -f http://localhost:9223/json/version > /dev/null; then
    echo "Chrome CDP proxy is not accessible on port 9223"
    exit 1
fi

# Check if standalone CDP is working
if ! curl -s -f http://localhost:9221/json/version > /dev/null; then
    echo "Standalone CDP is not accessible on port 9221"
    exit 1
fi

# Check if CDP proxy is rewriting URLs correctly
CDP_RESPONSE=$(curl -s http://localhost:9223/json 2>/dev/null || echo "[]")
if echo "$CDP_RESPONSE" | grep -q "localhost"; then
    echo "Warning: CDP proxy may not be rewriting URLs correctly"
fi

echo "All services are healthy"
exit 0
