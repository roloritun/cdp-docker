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

# Check if browser API is running (more reliable than CDP check)
if ! pgrep -f "browser_api.main" > /dev/null; then
    echo "Browser API is not running"
    exit 1
fi

echo "All services are healthy"
exit 0
