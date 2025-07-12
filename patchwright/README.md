# Patchright CDP + noVNC Container

A Docker container with Patchright browser automation, Chrome DevTools Protocol (CDP), and noVNC for remote desktop access. Optimized for Daytona and browser-use library integration.

## Features

- 🚀 **Patchright & Playwright**: Both libraries for browser automation
- 🔧 **Chrome CDP**: DevTools Protocol on port 9222 for direct browser control
- 🖥️ **noVNC**: Web-based VNC client on port 6080
- 🔌 **API Server**: FastAPI server on port 8000 for automation endpoints
- 📱 **Daytona Compatible**: Ready for Daytona cloud development environments

## Quick Start

### Using Docker Compose

```bash
# Build and run
docker-compose up --build

# Run in detached mode
docker-compose up -d --build
```

### Using Docker

```bash
# Build the image
docker build -t patchright-cdp:1.0.0 .

# Run the container
docker run -d \
  --name patchright-cdp \
  -p 6080:6080 \
  -p 5901:5901 \
  -p 9222:9222 \
  -p 8000:8000 \
  --shm-size=2g \
  patchright-cdp:1.0.0
```

## Accessing Services

- **noVNC Web Interface**: http://localhost:6080
- **Chrome CDP**: http://localhost:9222
- **API Server**: http://localhost:8000
- **VNC Direct**: localhost:5901

## Browser-use Integration

Connect browser-use to the CDP endpoint:

```python
from browser_use import Browser

# Connect to the CDP endpoint
browser = Browser(
    cdp_endpoint="http://localhost:9222",
    headless=False  # Since we have noVNC for viewing
)
```

## API Endpoints

### Main API Server (Port 8000)
- `GET /` - Health check
- `GET /browser/status` - Browser connection status
- `POST /browser/new_page` - Create new page
- `POST /browser/navigate` - Navigate to URL
- `GET /cdp/info` - CDP connection information

### Browser API Server (Port 8080)
- Browser automation actions via Patchright
- Page interaction endpoints
- Content extraction and manipulation
- Screenshot and PDF generation

## Daytona Usage

This container is configured for Daytona with:
- Platform: linux/amd64
- Proper labels for Daytona compatibility
- Health checks for service monitoring
- Exposed ports for web access

## Environment Variables

- `DISPLAY`: X11 display (default: :99)
- `VNC_PORT`: VNC server port (default: 5901)
- `NOVNC_PORT`: noVNC web port (default: 6080)
- `CDP_PORT`: Chrome CDP port (default: 9222)
- `API_PORT`: API server port (default: 8000)
- `CDP_API_PORT`: CDP API server port (default: 8080)

## Directory Structure

```
/workspace           # Working directory for automation scripts
/app                # Application files
/opt/novnc          # noVNC installation
/ms-playwright      # Patchright browser binaries
/tmp/chrome-profile # Chrome user profile directory
```
