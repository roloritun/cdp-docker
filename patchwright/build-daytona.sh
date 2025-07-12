#!/bin/bash
set -e

echo "🏗️  Building Multi-Platform Playwright/Patchright CDP + noVNC Container for Daytona"
echo "====================================================================================="

# Check if Docker buildx is available
if ! docker buildx version > /dev/null 2>&1; then
    echo "❌ Docker buildx is not available. Please install Docker Desktop or enable buildx."
    exit 1
fi

# Create a new builder if it doesn't exist
if ! docker buildx inspect daytona-builder > /dev/null 2>&1; then
    echo "📦 Creating multi-platform builder..."
    docker buildx create --name daytona-builder --driver docker-container --bootstrap
fi

# Use the builder
docker buildx use daytona-builder

# Use date-based versioning for Daytona snapshots
VERSION_TAG="${VERSION_TAG:-$(date +%Y.%m.%d)}"
BUILD_TAG="${BUILD_TAG:-${VERSION_TAG}-$(date +%H%M)}"
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Build for AMD64 (required by Daytona)
echo "🔨 Building AMD64 image for Daytona deployment..."
echo "   Version: ${VERSION_TAG}"
echo "   Build: ${BUILD_TAG}"
echo "   Date: ${BUILD_DATE}"

docker buildx build \
    --platform linux/amd64 \
    -f Dockerfile.playwright-cdp-novnc \
    --build-arg VERSION_TAG=${VERSION_TAG} \
    --build-arg BUILD_DATE=${BUILD_DATE} \
    -t cr.app.daytona.io/sbox-transient/playwright-cdp-novnc:${VERSION_TAG} \
    -t cr.app.daytona.io/sbox-transient/playwright-cdp-novnc:${BUILD_TAG} \
    -t cr.app.daytona.io/sbox-transient/playwright-cdp-novnc:latest \
    --load \
    .

echo "✅ AMD64 build completed successfully!"
echo ""
echo "🎯 Daytona Deployment Options:"
echo ""
echo "1️⃣  Push to Daytona using CLI:"
echo "   daytona snapshot push cr.app.daytona.io/sbox-transient/playwright-cdp-novnc:${VERSION_TAG} -n playwright-browser-automation-${VERSION_TAG}"
echo ""
echo "2️⃣  Create from Dockerfile:"
echo "   daytona snapshot create playwright-browser-automation-${VERSION_TAG} --dockerfile ./patchwright/Dockerfile.playwright-cdp-novnc --context ./patchwright"
echo ""
echo "3️⃣  Push to Docker Hub first (optional):"
echo "   docker tag cr.app.daytona.io/sbox-transient/playwright-cdp-novnc:${VERSION_TAG} yourusername/playwright-cdp-novnc:${VERSION_TAG}"
echo "   docker push yourusername/playwright-cdp-novnc:${VERSION_TAG}"
echo "   # Then use in Daytona: yourusername/playwright-cdp-novnc:${VERSION_TAG}"
echo ""
echo "📋 After deployment, your Daytona sandbox will have:"
echo "  📺 noVNC Web UI: Available on port 6080"
echo "  🔧 VNC Direct:   Available on port 5901"
echo "  🌐 CDP Endpoint: Available on port 9223"
echo "  📡 API Server:   Available on port 8000"
echo "  💻 Workspace:    /workspace directory"
echo ""
echo "🏥 Health check: GET /health endpoint"
echo "📚 API docs: GET /docs endpoint"
echo ""
echo "🏷️  Built tags:"
echo "   - cr.app.daytona.io/sbox-transient/playwright-cdp-novnc:${VERSION_TAG} (version tag)"
echo "   - cr.app.daytona.io/sbox-transient/playwright-cdp-novnc:${BUILD_TAG} (build tag)"
echo "   - cr.app.daytona.io/sbox-transient/playwright-cdp-novnc:latest (latest tag)"
